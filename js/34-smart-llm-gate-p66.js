(() => {
  "use strict";

  const VERSION="p6.9-event-driven-reasoning";
  const PROVIDER_ID="typhoon-byok";
  const BACKGROUND_MIN_REPLAN_TICKS=12;
  const URGENT_MIN_REPLAN_TICKS=2;
  const REUSABLE_ACTIONS=new Set(["MOVE","GATHER","REST","WAIT","HEAL","BUILD"]);
  const URGENT_REASONS=new Set(["action-failed","urgent-message","environment-change","entered-critical"]);
  const URGENT_MESSAGE_INTENTS=new Set(["WARN","REQUEST_HELP"]);

  const existing=runtime.registry.get(PROVIDER_ID);
  if(!existing?.adapter||typeof existing.adapter.decide!=="function")return;
  const upstream=existing.adapter;
  const cache=new Map();
  const stats={
    realCalls:0,reuses:0,holds:0,bootstrap:0,triggered:0,
    suppressedNonUrgentMessages:0,suppressedFacts:0,
    byReason:{},lastReason:null,lastRealAt:null
  };

  const incReason=reason=>{stats.byReason[reason]=(stats.byReason[reason]||0)+1;stats.lastReason=reason};
  const sessionKey=request=>`${request?.simulation?.id||"?"}:${request?.agent?.id||"?"}:${request?.sessionId||"?"}`;
  const critical=request=>{
    const s=request?.observation?.self||{};
    return Number(s.hp)<45||Number(s.thirst)>78||Number(s.hunger)>80;
  };
  const storm=request=>!!request?.observation?.environment?.stormActive;
  const clone=value=>JSON.parse(JSON.stringify(value));

  function urgentMessage(request){
    const messages=request?.observation?.messages||[];
    return messages.find(m=>Number(m?.urgency)>=.8||URGENT_MESSAGE_INTENTS.has(String(m?.intent||"")))||null;
  }

  function rebindResponse(entry,request){
    const next=clone(entry.response);
    const tick=Number(request.simulation.tick||0);
    next.requestId=request.requestId;
    next.agentId=request.agent.id;
    next.tick=tick;
    next.provider=PROVIDER_ID;
    if(next.decision){
      const remaining=Math.max(1,Number(entry.nextDueTick||tick+1)-tick);
      next.decision.replanAfterTicks=remaining;
    }
    next.diagnostics={
      ...(next.diagnostics||{}),
      decisionSource:"cached-llm-reuse",
      reusedFromTick:Number(entry.response?.tick??-1),
      originalReplanDueTick:Number(entry.nextDueTick||-1)
    };
    return next;
  }

  function holdResponse(entry,request){
    const tick=Number(request.simulation.tick||0);
    const c=entry?.response?.decision?.cognition||{};
    const remaining=Math.max(1,Number(entry?.nextDueTick||tick+1)-tick);
    return {
      protocol:PROTOCOL.decisionResponse,
      requestId:request.requestId,
      agentId:request.agent.id,
      tick,
      provider:PROVIDER_ID,
      decision:{
        action:{protocol:PROTOCOL.action,type:ACTION.WAIT,payload:{}},
        cognition:{
          goal:String(c.goal||request?.memory?.currentGoal||"observe").slice(0,80),
          reason:"continue existing LLM plan without repeating a one-shot action",
          plan:String(c.plan||request?.memory?.currentPlan||"wait for next reasoning event").slice(0,220),
          thought:""
        },
        thought:"",
        reason:"continue existing LLM plan without repeating a one-shot action",
        confidence:Number(entry?.response?.decision?.confidence||.7),
        replanAfterTicks:remaining
      },
      diagnostics:{
        engine:"astralife-event-driven-gate",
        decisionSource:"cached-llm-one-shot-hold",
        reusedFromTick:Number(entry?.response?.tick??-1),
        originalReplanDueTick:Number(entry?.nextDueTick||-1)
      }
    };
  }

  function outcomeTrigger(request,context,entry){
    const agent=context?.agent;
    const outcome=agent?.runtime?.lastOutcome;
    if(!outcome?.actionId||outcome.actionId===entry.lastOutcomeActionId)return null;
    if(!outcome.ok)return "action-failed";

    const type=String(outcome.actionType||"");
    if(type==="MOVE"&&outcome.reached)return "plan-stage-complete";
    if(type==="GATHER"&&outcome.significant)return "plan-stage-complete";
    if(type==="DEPOSIT"||type==="CONSUME")return "plan-stage-complete";
    if(type==="BUILD"&&agent?.mind&&Number(agent.mind.replanAtTick)<=Number(request?.simulation?.tick||0))return "plan-stage-complete";
    if(type==="REST"&&agent?.mind&&Number(agent.mind.replanAtTick)<=Number(request?.simulation?.tick||0))return "plan-stage-complete";
    // SHARE is intentionally NOT a reasoning trigger. A normal social message
    // should not cause the sender and every receiver to fan out into new API calls.
    return null;
  }

  function triggerReason(request,context,entry){
    if(!entry)return "bootstrap";
    const tick=Number(request?.simulation?.tick||0);

    const outcomeReason=outcomeTrigger(request,context,entry);
    if(outcomeReason)return outcomeReason;

    const urgent=urgentMessage(request);
    if(urgent)return "urgent-message";

    const nowStorm=storm(request);
    if(nowStorm!==entry.storm)return "environment-change";

    const nowCritical=critical(request);
    if(nowCritical&&!entry.critical)return "entered-critical";

    if(tick>=entry.nextDueTick)return "scheduled-replan";
    return null;
  }

  function rememberReal(request,context,response,reason){
    const key=sessionKey(request);
    const outcome=context?.agent?.runtime?.lastOutcome;
    const lastRealTick=Number(request.simulation.tick||0);
    const requested=Math.max(1,Number(response?.decision?.replanAfterTicks||BACKGROUND_MIN_REPLAN_TICKS));
    const floor=URGENT_REASONS.has(reason)?URGENT_MIN_REPLAN_TICKS:BACKGROUND_MIN_REPLAN_TICKS;
    const effectiveReplan=Math.max(floor,requested);
    cache.set(key,{
      response:clone(response),
      lastRealTick,
      nextDueTick:lastRealTick+effectiveReplan,
      storm:storm(request),
      critical:critical(request),
      lastOutcomeActionId:outcome?.actionId||null,
      reason
    });
  }

  class EventDrivenSmartGateProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return typeof upstream.isConfigured==="function"?upstream.isConfigured():true}
    decide(request,context){
      const key=sessionKey(request);
      const entry=cache.get(key)||null;
      const reason=triggerReason(request,context,entry);

      if(!reason&&entry){
        const actionType=String(entry.response?.decision?.action?.type||"");
        if(REUSABLE_ACTIONS.has(actionType)){
          stats.reuses++;
          incReason("reuse");
          return rebindResponse(entry,request);
        }
        stats.holds++;
        incReason("one-shot-hold");
        return holdResponse(entry,request);
      }

      // New facts and ordinary messages are intentionally absorbed by Memory.
      // They are included in the next scheduled/urgent LLM turn rather than
      // immediately creating more API traffic.
      const newFacts=request?.memory?.newFactKeys||[];
      if(newFacts.length)stats.suppressedFacts+=newFacts.length;
      const messages=request?.observation?.messages||[];
      if(messages.length&&!urgentMessage(request))stats.suppressedNonUrgentMessages+=messages.length;

      if(reason==="bootstrap")stats.bootstrap++;else stats.triggered++;
      stats.realCalls++;
      incReason(reason||"real");
      stats.lastRealAt=Date.now();
      return Promise.resolve(upstream.decide(request,context)).then(response=>{
        rememberReal(request,context,response,reason||"real");
        return response;
      });
    }
    status(){
      const upstreamStatus=typeof upstream.status==="function"?upstream.status():{};
      return {
        version:VERSION,
        cacheSize:cache.size,
        stats:{...stats,byReason:{...stats.byReason}},
        limits:{backgroundMinReplanTicks:BACKGROUND_MIN_REPLAN_TICKS,urgentMinReplanTicks:URGENT_MIN_REPLAN_TICKS},
        upstream:upstreamStatus
      };
    }
  }

  const gated=new EventDrivenSmartGateProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,gated,{
    label:"Typhoon 2.5 · event-driven reasoning",
    async:true,
    description:"Reason on meaningful events and plan-stage completion; reuse safe actions between events without periodic herd refresh"
  });

  window.AstraLifeLLMGate=Object.freeze({
    version:VERSION,
    status:()=>gated.status(),
    clear:()=>{cache.clear();return true},
    policy:Object.freeze({
      realTriggers:["bootstrap","action-failed","plan-stage-complete","urgent-message","environment-change","entered-critical","scheduled-replan"],
      ignoredImmediateTriggers:["ordinary-message","new-fact","share-success","periodic-max-stale","selected-refresh","critical-refresh"],
      reusableActions:[...REUSABLE_ACTIONS],
      admission:"no batch/defer; event-driven reasoning only; no periodic herd refresh; full-throughput dispatcher remains available when real reasoning is required"
    })
  });
})();

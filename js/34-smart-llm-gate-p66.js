(() => {
  "use strict";

  const VERSION="p6.7-staggered-llm-admission";
  const PROVIDER_ID="typhoon-byok";
  const BASE_MAX_STALE_TICKS=6;
  const STALE_JITTER_TICKS=4;
  const SELECTED_MAX_STALE_TICKS=3;
  const CRITICAL_REFRESH_TICKS=2;
  const BOOTSTRAP_SPREAD_TICKS=6;
  const SOFT_TOTAL_QUEUE=9;
  const SOFT_WORKER_QUEUE=3;
  const REUSABLE_ACTIONS=new Set(["MOVE","GATHER","REST","WAIT"]);
  const URGENT_REASONS=new Set([
    "action-failed","new-message","new-fact","environment-change",
    "entered-critical","one-shot-action","one-shot-outcome"
  ]);

  const existing=runtime.registry.get(PROVIDER_ID);
  if(!existing?.adapter||typeof existing.adapter.decide!=="function")return;
  const upstream=existing.adapter;
  const cache=new Map();
  const stats={
    realCalls:0,reuses:0,bootstrap:0,triggered:0,
    deferred:0,deferredBootstrap:0,pressureReuses:0,syntheticWaits:0,
    byReason:{},lastReason:null,lastRealAt:null,lastDeferredReason:null
  };

  const incReason=reason=>{stats.byReason[reason]=(stats.byReason[reason]||0)+1;stats.lastReason=reason};
  const sessionKey=request=>`${request?.simulation?.id||"?"}:${request?.agent?.id||"?"}:${request?.sessionId||"?"}`;
  const messageSig=request=>(request?.observation?.messages||[]).map(m=>m.id).sort((a,b)=>a-b).join(",");
  const factSig=request=>(request?.memory?.newFactKeys||[]).slice().sort().join("|");
  const critical=request=>{
    const s=request?.observation?.self||{};
    return Number(s.hp)<45||Number(s.thirst)>78||Number(s.hunger)>80;
  };
  const storm=request=>!!request?.observation?.environment?.stormActive;
  const selected=request=>Number(runtime.selectedAgentId)===Number(request?.agent?.id);
  const staleThresholdFor=request=>BASE_MAX_STALE_TICKS+((Math.max(1,Number(request?.agent?.id)||1)-1)%STALE_JITTER_TICKS);
  // Group Agents in triples so every bootstrap slot admits A/B/C together.
  const bootstrapSlotFor=request=>Math.floor((Math.max(1,Number(request?.agent?.id)||1)-1)/3)%BOOTSTRAP_SPREAD_TICKS;

  function clone(value){return JSON.parse(JSON.stringify(value))}

  function rebindResponse(entry,request,source="cached-llm-reuse",extra={}){
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
      decisionSource:source,
      reusedFromTick:Number(entry.response?.tick??-1),
      originalReplanDueTick:Number(entry.nextDueTick||-1),
      ...extra
    };
    return next;
  }

  function deferredWait(request,reason,why){
    const goal=String(request?.memory?.currentGoal||"observe").slice(0,80)||"observe";
    const goalReason=String(request?.memory?.goalReason||"").slice(0,180);
    const plan=String(request?.memory?.currentPlan||"wait for Typhoon reasoning slot").slice(0,220);
    return {
      protocol:PROTOCOL.decisionResponse,
      requestId:request.requestId,
      agentId:request.agent.id,
      tick:request.simulation.tick,
      provider:PROVIDER_ID,
      decision:{
        action:{protocol:PROTOCOL.action,type:ACTION.WAIT,payload:{}},
        cognition:{goal,reason:goalReason||"reasoning admission deferred",plan,thought:""},
        thought:"",
        reason:goalReason||"reasoning admission deferred",
        confidence:.5,
        replanAfterTicks:1
      },
      diagnostics:{
        engine:"astralife-admission-control",
        decisionSource:"deferred-admission",
        deferredReason:reason,
        deferredBecause:why
      }
    };
  }

  function queuePressure(request){
    const status=window.AstraLifeTyphoonQueue?.status?.();
    if(!status)return {pressured:false,total:0,workerQueued:0,worker:null};
    const workerName=window.AstraLifeTyphoonQueue?.workerForAgent?.(request?.agent?.id);
    const worker=(status.workers||[]).find(w=>w.name===workerName)||null;
    const total=Number(status.queueDepth||0);
    const workerQueued=Number(worker?.queued||0);
    return {
      pressured:total>=SOFT_TOTAL_QUEUE||workerQueued>=SOFT_WORKER_QUEUE,
      total,workerQueued,worker:workerName||null
    };
  }

  function triggerReason(request,context,entry){
    if(!entry)return "bootstrap";
    const tick=Number(request?.simulation?.tick||0);
    const agent=context?.agent;
    const elapsed=tick-entry.lastRealTick;
    const actionType=String(entry.response?.decision?.action?.type||"");
    if(!REUSABLE_ACTIONS.has(actionType))return "one-shot-action";

    const outcome=agent?.runtime?.lastOutcome;
    if(outcome?.actionId&&outcome.actionId!==entry.lastOutcomeActionId){
      if(!outcome.ok)return "action-failed";
      if(outcome.significant)return "significant-outcome";
      if(!REUSABLE_ACTIONS.has(String(outcome.actionType||"")))return "one-shot-outcome";
    }

    const msg=messageSig(request);
    if(msg&&msg!==entry.messageSig)return "new-message";
    const facts=factSig(request);
    if(facts&&facts!==entry.factSig)return "new-fact";
    const nowStorm=storm(request);
    if(nowStorm!==entry.storm)return "environment-change";

    const nowCritical=critical(request);
    if(nowCritical&&!entry.critical)return "entered-critical";
    if(nowCritical&&elapsed>=CRITICAL_REFRESH_TICKS)return "critical-refresh";

    if(tick>=entry.nextDueTick)return "scheduled-replan";
    if(agent?.mind&&Number(agent.mind.replanAtTick)<=tick)return "scheduled-replan";
    if(selected(request)&&elapsed>=SELECTED_MAX_STALE_TICKS)return "selected-refresh";
    if(elapsed>=staleThresholdFor(request))return "max-stale-refresh";
    return null;
  }

  function rememberReal(request,context,response,reason){
    if(String(response?.diagnostics?.decisionSource||"").startsWith("deferred-"))return;
    const key=sessionKey(request);
    const outcome=context?.agent?.runtime?.lastOutcome;
    const lastRealTick=Number(request.simulation.tick||0);
    const replanAfter=Math.max(1,Number(response?.decision?.replanAfterTicks||1));
    cache.set(key,{
      response:clone(response),
      lastRealTick,
      nextDueTick:lastRealTick+replanAfter,
      messageSig:messageSig(request),
      factSig:factSig(request),
      storm:storm(request),
      critical:critical(request),
      lastOutcomeActionId:outcome?.actionId||null,
      reason
    });
  }

  function defer(request,entry,reason,why){
    stats.deferred++;
    stats.lastDeferredReason=`${reason}:${why}`;
    incReason(`defer:${reason}`);
    if(reason==="bootstrap")stats.deferredBootstrap++;
    if(entry){
      stats.reuses++;
      stats.pressureReuses++;
      return rebindResponse(entry,request,"cached-llm-admission-reuse",{deferredReason:reason,deferredBecause:why});
    }
    stats.syntheticWaits++;
    return deferredWait(request,reason,why);
  }

  function shouldDefer(request,context,entry,reason){
    if(context?.forceRealReasoning)return null;
    if(selected(request)||critical(request)||URGENT_REASONS.has(reason))return null;

    const tick=Number(request?.simulation?.tick||0);
    if(reason==="bootstrap"&&tick%BOOTSTRAP_SPREAD_TICKS!==bootstrapSlotFor(request)){
      return "bootstrap-stagger";
    }

    const pressure=queuePressure(request);
    if(pressure.pressured){
      return `queue-pressure:${pressure.worker||"?"}:${pressure.workerQueued}/${pressure.total}`;
    }
    return null;
  }

  class SmartGateProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return typeof upstream.isConfigured==="function"?upstream.isConfigured():true}
    decide(request,context){
      const key=sessionKey(request);
      const entry=cache.get(key)||null;
      const reason=triggerReason(request,context,entry);
      if(!reason&&entry){
        stats.reuses++;
        incReason("reuse");
        return rebindResponse(entry,request);
      }

      const deferredBecause=shouldDefer(request,context,entry,reason||"real");
      if(deferredBecause)return defer(request,entry,reason||"real",deferredBecause);

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
        limits:{
          baseMaxStaleTicks:BASE_MAX_STALE_TICKS,
          staleJitterTicks:STALE_JITTER_TICKS,
          selectedMaxStaleTicks:SELECTED_MAX_STALE_TICKS,
          criticalRefreshTicks:CRITICAL_REFRESH_TICKS,
          bootstrapSpreadTicks:BOOTSTRAP_SPREAD_TICKS,
          softTotalQueue:SOFT_TOTAL_QUEUE,
          softWorkerQueue:SOFT_WORKER_QUEUE
        },
        upstream:upstreamStatus
      };
    }
  }

  const gated=new SmartGateProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,gated,{
    label:"Typhoon 2.5 · staggered smart gate",
    async:true,
    description:"Staggered admission keeps the real Typhoon queue short; urgent triggers reason immediately and safe plans reuse between slots"
  });

  window.AstraLifeLLMGate=Object.freeze({
    version:VERSION,
    status:()=>gated.status(),
    clear:()=>{cache.clear();return true},
    staleTicksForAgent:agentId=>BASE_MAX_STALE_TICKS+((Math.max(1,Number(agentId)||1)-1)%STALE_JITTER_TICKS),
    bootstrapSlotForAgent:agentId=>Math.floor((Math.max(1,Number(agentId)||1)-1)/3)%BOOTSTRAP_SPREAD_TICKS,
    policy:Object.freeze({
      realTriggers:["bootstrap","action-failed","significant-outcome","new-message","new-fact","environment-change","entered-critical","critical-refresh","scheduled-replan","selected-refresh","max-stale-refresh","one-shot-action","one-shot-outcome"],
      urgentTriggers:[...URGENT_REASONS],
      reusableActions:[...REUSABLE_ACTIONS],
      admission:"balanced A/B/C bootstrap stagger + queue-pressure backoff; no local fallback for ordinary deferral"
    })
  });
})();

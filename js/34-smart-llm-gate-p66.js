(() => {
  "use strict";

  const VERSION="p6.6-smart-llm-gate";
  const PROVIDER_ID="typhoon-byok";
  const MAX_STALE_TICKS=6;
  const SELECTED_MAX_STALE_TICKS=3;
  const CRITICAL_REFRESH_TICKS=2;
  const REUSABLE_ACTIONS=new Set(["MOVE","GATHER","REST","WAIT"]);

  const existing=runtime.registry.get(PROVIDER_ID);
  if(!existing?.adapter||typeof existing.adapter.decide!=="function")return;
  const upstream=existing.adapter;
  const cache=new Map();
  const stats={realCalls:0,reuses:0,bootstrap:0,triggered:0,byReason:{},lastReason:null,lastRealAt:null};

  const incReason=reason=>{stats.byReason[reason]=(stats.byReason[reason]||0)+1;stats.lastReason=reason};
  const sessionKey=request=>`${request?.simulation?.id||"?"}:${request?.agent?.id||"?"}:${request?.sessionId||"?"}`;
  const messageSig=request=>(request?.observation?.messages||[]).map(m=>m.id).sort((a,b)=>a-b).join(",");
  const factSig=request=>(request?.memory?.newFactKeys||[]).slice().sort().join("|");
  const critical=request=>{
    const s=request?.observation?.self||{};
    return Number(s.hp)<45||Number(s.thirst)>78||Number(s.hunger)>80;
  };
  const storm=request=>!!request?.observation?.environment?.stormActive;

  function clone(value){return JSON.parse(JSON.stringify(value))}

  function rebindResponse(response,request){
    const next=clone(response);
    next.requestId=request.requestId;
    next.agentId=request.agent.id;
    next.tick=request.simulation.tick;
    next.provider=PROVIDER_ID;
    next.diagnostics={
      ...(next.diagnostics||{}),
      decisionSource:"cached-llm-reuse",
      reusedFromTick:Number(response?.tick??-1)
    };
    return next;
  }

  function triggerReason(request,context,entry){
    if(!entry)return "bootstrap";
    const tick=Number(request?.simulation?.tick||0);
    const agent=context?.agent;
    const elapsed=tick-entry.lastRealTick;
    const selected=Number(runtime.selectedAgentId)===Number(request?.agent?.id);
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

    if(agent?.mind&&Number(agent.mind.replanAtTick)<=tick)return "scheduled-replan";
    if(selected&&elapsed>=SELECTED_MAX_STALE_TICKS)return "selected-refresh";
    if(elapsed>=MAX_STALE_TICKS)return "max-stale-refresh";
    return null;
  }

  function rememberReal(request,context,response,reason){
    const key=sessionKey(request);
    const outcome=context?.agent?.runtime?.lastOutcome;
    cache.set(key,{
      response:clone(response),
      lastRealTick:Number(request.simulation.tick||0),
      messageSig:messageSig(request),
      factSig:factSig(request),
      storm:storm(request),
      critical:critical(request),
      lastOutcomeActionId:outcome?.actionId||null,
      reason
    });
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
        return rebindResponse(entry.response,request);
      }
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
        limits:{maxStaleTicks:MAX_STALE_TICKS,selectedMaxStaleTicks:SELECTED_MAX_STALE_TICKS,criticalRefreshTicks:CRITICAL_REFRESH_TICKS},
        upstream:upstreamStatus
      };
    }
  }

  const gated=new SmartGateProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,gated,{
    label:"Typhoon 2.5 · smart gated",
    async:true,
    description:"Real Typhoon reasoning on meaningful triggers; safe continuous actions reuse the latest validated LLM decision between refreshes"
  });

  window.AstraLifeLLMGate=Object.freeze({
    version:VERSION,
    status:()=>gated.status(),
    clear:()=>{cache.clear();return true},
    policy:Object.freeze({
      realTriggers:["bootstrap","action-failed","significant-outcome","new-message","new-fact","environment-change","entered-critical","critical-refresh","scheduled-replan","selected-refresh","max-stale-refresh","one-shot-action","one-shot-outcome"],
      reusableActions:[...REUSABLE_ACTIONS]
    })
  });
})();

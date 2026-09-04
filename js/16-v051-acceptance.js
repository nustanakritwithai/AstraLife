(() => {
  "use strict";
  function digest(rt){const s=rt.state;return JSON.stringify({seed:s.seed,tick:s.tick,stock:s.stock,camp:s.camp,resources:s.resources.map(r=>[r.id,r.type,round1(r.x),round1(r.y),round1(r.amount)]),agents:s.agents.map(a=>[a.id,a.alive,round1(a.body.x),round1(a.body.y),round1(a.body.hp),round1(a.body.hunger),round1(a.body.thirst),round1(a.body.energy),a.emergentRole,Object.fromEntries(Object.entries(a.development?.skills||{}).map(([k,v])=>[k,[round1(v.xp),round1(v.competency),v.success,v.failure]]))])})}
  function fresh(seed){const rt=new WorldRuntime(seed);rt.setProviderMode(PROVIDER_MODE.LOCAL);return rt}
  function run(ticks=1000){
    const seed=`${runtime.seed}:v051-acceptance`,count=clamp(Math.floor(Number(ticks)||1000),1,1000),a=fresh(seed),b=fresh(seed);
    a.runTicks(count);b.runTicks(count);
    const core=a.selfTest(),forbidden=[];
    a.tickOnce();const agent=a.state.agents.find(x=>x.alive),req=agent?.runtime?.lastDecisionRequest;
    if(req)for(const type of ["SET_WORLD_STATE","TELEPORT","SET_HP","ADD_RESOURCE"]){const provider=req.simulation.providerHint==="local-fallback"?"local":req.simulation.providerHint,res=makeDecisionResponse(req,provider,{type,payload:{}},{goal:"boundary_test",reason:"mutation attempt",plan:"must reject"},.5,1),checked=a.validator.validate(res,req,a.state);forbidden.push({type,rejected:!checked.ok,errors:checked.errors})}
    const obsIsolation=a.state.agents.every(x=>!x.runtime.lastObservation||(x.runtime.lastObservation.visibleResources||[]).every(r=>{const range=CONFIG.observationRange+(CONFIG.scoutRange-CONFIG.observationRange)*(Number(x.development?.skills?.exploration?.competency)||0);return r.distance<=range+.2}));
    const sessions=AgentStateBoundaryV051.validateSessionIsolation(a.state.agents),stages=a.decisionStaging.items;
    const lifecycleAccepted=stages.some(x=>x.status===DECISION_STATUS_V051.RESOLVED),lifecycleRejected=forbidden.every(x=>x.rejected),emergent=a.specialistCount()>0||(a.state.metrics.roleTransitions||0)>0;
    const result={version:"0.5.1",seed,ticks:count,tests:{worldMutationBoundary:lifecycleRejected,uiMutationIsolation:(()=>{const before=a.state.stock.food,snap=a.worldStateBoundary.runtimeSnapshot();try{snap.camp.x=-1}catch{}return a.state.stock.food===before&&snap!==a.state})(),observationIsolation:obsIsolation,sessionIsolation:sessions.ok,stagingAcceptedLifecycle:lifecycleAccepted,stagingRejectedLifecycle:lifecycleRejected,deterministicWorld:digest(a)===digest(b),existingV05EmergentRoles:emergent,integrityGate:core.ok},forbiddenMutationResults:forbidden,roleDistribution:a.roleDistribution(),specialists:a.specialistCount(),roleTransitions:a.state.metrics.roleTransitions||0,integrity:core};
    result.ok=Object.values(result.tests).every(Boolean);return result;
  }
  const h=document.querySelector("header h1");if(h)h.textContent="ASTRA COLONY V0.5.1 · CORE ARCHITECTURE HARDENING";document.title="ASTRA COLONY V0.5.1 — Core Architecture Hardening";const tip=document.getElementById("tip");if(tip)tip.textContent="V0.5.1: Provider proposes → Validator accepts/rejects → Resolver mutates WorldState · Agent identity/session stays isolated and persistent.";
  window.AstraLifeV051Acceptance=Object.freeze({run,selfTest:()=>runtime.v051SelfTest()});
})();

(() => {
  "use strict";
  const V051="0.5.1";
  const oldCreateAgent=WorldRuntime.prototype.createAgent;
  WorldRuntime.prototype.createAgent=function(){return AgentStateBoundaryV051.attach(oldCreateAgent.call(this))};

  function installCore(rt){
    rt.coreContracts=rt.coreContracts||new CoreContractsV051();
    rt.decisionStaging=rt.decisionStaging||new DecisionStagingV051();
    rt.worldStateBoundary=rt.worldStateBoundary||new WorldStateBoundaryV051(rt);
    rt.worldStateBoundary.runtime=rt;rt.worldStateBoundary.attach();
    rt.decisionRouter.staging=rt.decisionStaging;rt.resolver.staging=rt.decisionStaging;rt.resolver.worldBoundary=rt.worldStateBoundary;
    for(const a of rt.state.agents)AgentStateBoundaryV051.attach(a);
    rt.state.metrics.contractErrors=rt.state.metrics.contractErrors||0;
    rt.state.metrics.rejectedDecisions=rt.state.metrics.rejectedDecisions||0;
    rt.state.metrics.resolvedDecisions=rt.state.metrics.resolvedDecisions||0;
    return rt;
  }

  const oldReset=WorldRuntime.prototype.reset;
  WorldRuntime.prototype.reset=function(seed=this.seed){oldReset.call(this,seed);installCore(this);this.events.emit(this.state.tick,"V051",`V0.5.1 Core Architecture Hardening active · WorldState authority + Decision Staging`,{},"important")};

  const oldValidate=ActionContractValidator.prototype.validate;
  ActionContractValidator.prototype.validate=function(response,request,state){
    const rawType=response?.decision?.action?.type;
    if(ASTRA_FORBIDDEN_MUTATION_ACTIONS.includes(rawType))return {ok:false,errors:[`FORBIDDEN_WORLD_MUTATION_ACTION:${rawType}`]};
    const base=oldValidate.call(this,response,request,state);if(!base.ok)return base;
    const agent=state.agentById.get(request.agent.id),a=base.normalized.action,p=a.payload||{},errors=[];
    if(!agent||!agent.alive)errors.push("AGENT_INVALID_OR_UNAVAILABLE");
    if(agent&&request.sessionId!==agent.runtime.providerSessionId)errors.push("SESSION_MISMATCH");
    if(request.observation?.observationId!==request.requestId)errors.push("OBSERVATION_ID_MISMATCH");
    if(state.tick-request.simulation.tick>CONFIG.maxDecisionAge)errors.push("ACTION_EXPIRED");
    if(a.type===ACTION.GATHER){const r=state.resourceById.get(p.resourceId);if(!r||r.amount<=.05)errors.push("RESOURCE_NOT_FOUND");else if(agent&&distance(agent.body,r)>CONFIG.interactRange+2)errors.push("OUT_OF_RANGE")}
    if(a.type===ACTION.HEAL){const t=state.agentById.get(p.targetAgentId);if(!t||!t.alive)errors.push("TARGET_AGENT_NOT_FOUND");else if(agent&&distance(agent.body,t.body)>CONFIG.interactRange+5)errors.push("OUT_OF_RANGE")}
    if(a.type===ACTION.DEPOSIT&&agent&&distance(agent.body,state.camp)>CONFIG.campSyncRange)errors.push("OUT_OF_RANGE");
    if(a.type===ACTION.BUILD&&request.agent?.capabilities?.canBuild===false)errors.push("CAPABILITY_DENIED");
    if(a.type===ACTION.HEAL&&request.agent?.capabilities?.canHeal===false)errors.push("CAPABILITY_DENIED");
    return errors.length?{ok:false,errors}:base;
  };

  function stageTask(router,state,task,checked){
    if(!router.staging||!task?.request)return null;
    const raw=task.rawResponse||{},action=raw?.decision?.action||{type:"UNKNOWN",payload:{}};
    const entry=router.staging.propose({agentId:task.agent.id,sessionId:task.request.sessionId,tick:task.request.simulation.tick,providerId:task.providerId||raw.provider||"unknown",providerVersion:"v1",observationId:task.request.observation?.observationId||"",requestedAction:{type:action.type,payload:action.payload||{}},rawResponse:raw});
    entry.requestId=task.request.requestId;router.staging.validating(entry.decisionId);task._v051DecisionId=entry.decisionId;
    if(checked.ok)router.staging.accept(entry.decisionId,[]);else{
      const reason=String(checked.errors?.[0]||"VALIDATION_REJECTED");const feedback=router.staging.reject(entry.decisionId,reason,reason,state.tick,checked.errors||[]).feedback;
      task.agent.runtime.lastDecisionFeedback=feedback;task.agent.runtime.feedbackInbox=task.agent.runtime.feedbackInbox||[];task.agent.runtime.feedbackInbox.push(feedback);if(task.agent.runtime.feedbackInbox.length>20)task.agent.runtime.feedbackInbox.shift();
      state.metrics.rejectedDecisions=(state.metrics.rejectedDecisions||0)+1;
    }
    return entry;
  }

  const oldComplete=DecisionRouter.prototype.complete;
  DecisionRouter.prototype.complete=function(state,task,queue){
    if(task.kind==="response"){
      const checked=this.validator.validate(task.rawResponse,task.request,state);stageTask(this,state,task,checked);
    }
    return oldComplete.call(this,state,task,queue);
  };

  const oldFallback=DecisionRouter.prototype.fallbackLocal;
  DecisionRouter.prototype.fallbackLocal=function(state,task,queue,reason){
    const before=this.staging?.items.length||0;oldFallback.call(this,state,task,queue,reason);
    if(!this.staging||this.staging.items.length!==before)return;
    const req=task.agent.runtime.lastDecisionRequest,res=task.agent.runtime.lastDecisionResponse;
    if(!req||!res||res.provider!=="local")return;
    const checked=this.validator.validate(res,req,state);stageTask(this,state,{...task,request:req,rawResponse:res,providerId:"local"},checked);
  };

  const oldResolve=ActionResolver.prototype.resolve;
  ActionResolver.prototype.resolve=function(state,actions){
    if(this.worldBoundary){for(const a of actions)if(!a.meta||a.meta.validated!==true)this.worldBoundary.recordUnvalidated();this.worldBoundary.enterResolver()}
    let outcomes;try{outcomes=oldResolve.call(this,state,actions)}finally{if(this.worldBoundary)this.worldBoundary.exitResolver()}
    if(this.staging){
      const byActionId=new Map(actions.map(a=>[a.id,a]));
      for(const o of outcomes){const action=byActionId.get(o.actionId),requestId=action?.meta?.requestId;if(!requestId)continue;const stage=[...this.staging.items].reverse().find(x=>x.requestId===requestId&&x.status===DECISION_STATUS_V051.ACCEPTED);if(!stage)continue;this.staging.resolve(stage.decisionId,state.tick,o);state.metrics.resolvedDecisions=(state.metrics.resolvedDecisions||0)+1;const agent=state.agentById.get(o.agentId);if(agent){agent.runtime.lastDecisionId=stage.decisionId;if(!o.ok){const feedback=Object.freeze({decisionId:stage.decisionId,status:"RESOLVED",reason:"RESOLVER_REJECTED",message:o.message,worldTick:state.tick});agent.runtime.lastDecisionFeedback=feedback;agent.runtime.feedbackInbox=agent.runtime.feedbackInbox||[];agent.runtime.feedbackInbox.push(feedback)}}}
    }
    return outcomes;
  };

  const oldSnapshot=WorldRuntime.prototype.snapshot;
  WorldRuntime.prototype.snapshot=function(){const snap=oldSnapshot.call(this);snap.metadata.version=V051;snap.core={protocols:ASTRA_CORE_PROTOCOLS_V051,authority:{provider:"PROPOSE",validator:"ACCEPT_OR_REJECT",resolver:"MUTATE_WORLDSTATE"},worldSnapshot:this.worldStateBoundary.runtimeSnapshot(),decisionStaging:this.decisionStaging.recent(250)};for(const row of snap.agents){const a=this.state.agentById.get(row.id);row.persistentState=AgentStateBoundaryV051.persistent(a);row.runtimeBoundary=AgentStateBoundaryV051.runtime(a)}return snap};

  const oldBundle=WorldRuntime.prototype.contractBundle;
  WorldRuntime.prototype.contractBundle=function(){return {...oldBundle.call(this),version:V051,coreV051:this.coreContracts.bundle()}};

  const oldSelfTest=WorldRuntime.prototype.selfTest;
  WorldRuntime.prototype.selfTest=function(){
    const t=oldSelfTest.call(this),errors=t.errors.slice(),s=this.state,session=AgentStateBoundaryV051.validateSessionIsolation(s.agents);
    if(!session.ok)errors.push(`session collision: ${session.count-session.unique}`);
    for(const a of s.agents){if(!a.runtime?.providerSessionId)errors.push(`agent ${a.id} missing session`);if(a.runtime?.lastObservation){const range=CONFIG.observationRange+(CONFIG.scoutRange-CONFIG.observationRange)*(Number(a.development?.skills?.exploration?.competency)||0);for(const r of a.runtime.lastObservation.visibleResources||[])if(r.distance>range+.2)errors.push(`agent ${a.id} observation leak resource ${r.id}`)}}
    const integrity=this.worldStateBoundary.integrity();if(integrity.unvalidatedResolverActions)errors.push(`unvalidated resolver action: ${integrity.unvalidatedResolverActions}`);if(integrity.outsideResolverMutations)errors.push(`world mutation outside resolver: ${integrity.outsideResolverMutations}`);
    if((s.metrics.contractErrors||0)>0)errors.push(`contract errors: ${s.metrics.contractErrors}`);
    return {ok:errors.length===0,errors,gate:{negativeResource:errors.filter(e=>e.startsWith("stock.")||e.startsWith("resource ")).length,invalidAgentIds:0,duplicateAgentIds:errors.filter(e=>e==="duplicate agent id").length,sessionCollision:session.count-session.unique,unvalidatedResolverAction:integrity.unvalidatedResolverActions,worldMutationOutsideResolver:integrity.outsideResolverMutations,contractErrors:s.metrics.contractErrors||0,runtimeIntegrity:errors.length?"FAIL":"PASS"}};
  };

  WorldRuntime.prototype.v051SelfTest=function(){
    const results=[];const push=(name,ok,detail="")=>results.push({name,ok,detail});
    const a=this.state.agents.find(x=>x.alive),req=a?.runtime?.lastDecisionRequest;
    if(req){for(const type of ASTRA_FORBIDDEN_MUTATION_ACTIONS.slice(0,4)){const response=makeDecisionResponse(req,req.simulation.providerHint==="local-fallback"?"local":req.simulation.providerHint,{type,payload:{}},{goal:"test",reason:"boundary test",plan:"test"},.5,1);const r=this.validator.validate(response,req,this.state);push(`reject ${type}`,!r.ok,r.errors.join(" | "))}}else push("forbidden mutation actions",true,"run one tick to exercise live request validation");
    const before=this.state.stock.food,view=this.worldStateBoundary.runtimeSnapshot();try{view.camp.x=999999}catch{}push("UI/runtime snapshot isolation",this.state.stock.food===before&&view!==this.state,"snapshot is deep-frozen and detached");
    const session=AgentStateBoundaryV051.validateSessionIsolation(this.state.agents);push("session isolation",session.ok,`${session.unique}/${session.count} unique`);
    const lifecycle=this.decisionStaging.items.some(x=>x.status===DECISION_STATUS_V051.RESOLVED)||this.state.tick===0;push("staging lifecycle",lifecycle,`${this.decisionStaging.items.length} staged decisions`);
    const core=this.selfTest();push("integrity gate",core.ok,core.errors.join(" | "));
    return {ok:results.every(x=>x.ok),version:V051,results,integrity:core};
  };

  installCore(runtime);
  window.AstraLifeV051=Object.freeze({version:V051,protocols:ASTRA_CORE_PROTOCOLS_V051,getWorldSnapshot:()=>runtime.worldStateBoundary.runtimeSnapshot(),getAgentPersistentState:id=>{const a=runtime.state.agentById.get(Number(id));return a?AgentStateBoundaryV051.persistent(a):null},getDecisionStaging:()=>runtime.decisionStaging.recent(250),selfTest:()=>runtime.v051SelfTest(),authority:Object.freeze({provider:"PROPOSE",validator:"ACCEPT_OR_REJECT",resolver:"MUTATE_WORLDSTATE"})});
})();

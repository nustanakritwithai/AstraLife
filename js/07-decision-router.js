class DecisionRouter{
  constructor(registry,requestFactory,validator,memory,events){
    this.registry=registry;this.requestFactory=requestFactory;this.validator=validator;this.memory=memory;this.events=events;
    this.mode=PROVIDER_MODE.LOCAL;this.pending=new Map();this.ready=new Map();this.failed=new Map();this.epoch=1;this.lastWarningTick=-999;this.metrics=this.blankMetrics();
  }
  blankMetrics(){return {calls:0,accepted:0,invalid:0,fallbacks:0,providerErrors:0,pendingWaits:0,latencyTotalMs:0,latencySamples:0,byProvider:{}}}
  reset(events=this.events){this.events=events;this.pending.clear();this.ready.clear();this.failed.clear();this.epoch++;this.metrics=this.blankMetrics()}
  setMode(mode){
    const valid=[...Object.values(PROVIDER_MODE),...this.registry.list().filter(p=>p.kind==="custom").map(p=>`provider:${p.id}`)];
    if(!valid.includes(mode))throw new Error(`Unknown provider mode: ${mode}`);
    this.mode=mode;this.pending.clear();this.ready.clear();this.failed.clear();this.epoch++;
  }
  label(){
    return ({local:"LOCAL",[PROVIDER_MODE.ASTRA_SIM]:"ASTRA-SIM",[PROVIDER_MODE.HYBRID]:"HYBRID 20%",[PROVIDER_MODE.REMOTE]:"ASTRA HTTP"})[this.mode]||this.mode.replace(/^provider:/,"").toUpperCase();
  }
  count(providerId,field){
    const row=this.metrics.byProvider[providerId]||(this.metrics.byProvider[providerId]={calls:0,accepted:0,invalid:0,errors:0});row[field]=(row[field]||0)+1;
  }
  selectProvider(agent,observation){
    if(this.mode===PROVIDER_MODE.LOCAL)return "local";
    if(this.mode===PROVIDER_MODE.ASTRA_SIM)return "astra-sim";
    if(this.mode===PROVIDER_MODE.HYBRID){
      const critical=observation.self.hp<45||observation.self.hunger>80||observation.self.thirst>78||agent.mind.failedActions>2;
      return critical||agent.id%5===0?"astra-sim":"local";
    }
    if(this.mode===PROVIDER_MODE.REMOTE){
      const deliberate=agent.mind.goal==="orient"||agent.mind.replanAtTick<=observation.tick||(agent.runtime.lastOutcome&&!agent.runtime.lastOutcome.ok);
      return deliberate?"remote":"local";
    }
    if(this.mode.startsWith("provider:"))return this.mode.slice(9);
    return "local";
  }
  cleanup(state){
    for(const id of [...this.pending.keys()]){const a=state.agentById.get(id);if(!a||!a.alive)this.pending.delete(id)}
    for(const id of [...this.ready.keys()]){const a=state.agentById.get(id);if(!a||!a.alive)this.ready.delete(id)}
    for(const id of [...this.failed.keys()]){const a=state.agentById.get(id);if(!a||!a.alive)this.failed.delete(id)}
  }
  prepare(state,packet,summary){
    const {agent,observation}=packet;const context={agent,observation,summary,planner:packet.planner};
    if(this.ready.has(agent.id)){
      const ready=this.ready.get(agent.id);this.ready.delete(agent.id);agent.runtime.providerStatus="response-ready";
      return {kind:"response",agent,observation,summary,context,request:ready.request,providerId:ready.providerId,rawResponse:ready.response,latencyMs:ready.latencyMs};
    }
    if(this.failed.has(agent.id)){
      const failure=this.failed.get(agent.id);this.failed.delete(agent.id);agent.runtime.providerStatus="provider-error";
      const request=this.requestFactory.build(state,agent,observation,"local-fallback");agent.runtime.lastDecisionRequest=request;
      return {kind:"error",agent,observation,summary,context,request,providerId:failure.providerId,error:failure.error};
    }
    if(this.pending.has(agent.id)){agent.runtime.providerStatus="pending";return {kind:"pending",agent,observation,summary,context,providerId:this.pending.get(agent.id).providerId}}
    const providerId=this.selectProvider(agent,observation);const request=this.requestFactory.build(state,agent,observation,providerId);
    agent.runtime.lastDecisionRequest=request;agent.runtime.providerStatus="request-created";
    return {kind:"request",agent,observation,summary,context,request,providerId};
  }
  invoke(task){
    if(task.kind!=="request")return task;
    const entry=this.registry.get(task.providerId);
    if(!entry){task.kind="error";task.error=new Error(`provider ${task.providerId} not registered`);return task}
    if(typeof entry.adapter.isConfigured==="function"&&!entry.adapter.isConfigured()){
      task.kind="error";task.error=new Error(`${task.providerId} provider is not configured`);return task;
    }
    const started=performance.now();this.metrics.calls++;this.count(task.providerId,"calls");task.agent.runtime.providerStatus="provider-running";
    try{
      const result=entry.adapter.decide(task.request,task.context);
      if(result&&typeof result.then==="function"){
        const epoch=this.epoch,agentId=task.agent.id,request=task.request,providerId=task.providerId;
        this.pending.set(agentId,{request,providerId,started,epoch});task.kind="pending-started";task.agent.runtime.providerStatus="pending";task.agent.runtime.lastProvider=providerId;
        Promise.resolve(result).then(response=>{
          const pending=this.pending.get(agentId);if(!pending||pending.epoch!==epoch||this.epoch!==epoch)return;
          this.pending.delete(agentId);this.ready.set(agentId,{request,response,providerId,latencyMs:performance.now()-started});
        }).catch(error=>{
          const pending=this.pending.get(agentId);if(!pending||pending.epoch!==epoch||this.epoch!==epoch)return;
          this.pending.delete(agentId);this.failed.set(agentId,{request,providerId,error:error instanceof Error?error:new Error(String(error))});
        });
      }else{task.rawResponse=result;task.latencyMs=performance.now()-started;task.kind="response"}
    }catch(error){task.kind="error";task.error=error instanceof Error?error:new Error(String(error))}
    return task;
  }
  internalWait(state,task,queue,reason){
    queue.enqueue(state.tick,task.agent.id,ACTION.WAIT,{},reason,{provider:"runtime",validated:true});task.agent.runtime.lastActionType=ACTION.WAIT;
    this.memory.trace(task.agent,"PROVIDER",reason);
  }
  applyAccepted(state,task,normalized,queue,isFallback=false){
    const agent=task.agent,c=normalized.cognition;
    agent.mind.goal=c.goal;agent.mind.goalReason=c.reason;agent.mind.plan=c.plan;agent.mind.replanAtTick=state.tick+normalized.replanAfterTicks;
    if(normalized.action.type===ACTION.MOVE)agent.mind.target={x:normalized.action.payload.x,y:normalized.action.payload.y};
    queue.enqueue(state.tick,agent.id,normalized.action.type,normalized.action.payload,normalized.reason,{provider:normalized.provider,requestId:normalized.requestId,sourceTick:normalized.sourceTick,confidence:normalized.confidence,validated:true,fallback:isFallback});
    agent.runtime.lastActionType=normalized.action.type;agent.runtime.lastProvider=normalized.provider;agent.runtime.providerStatus=isFallback?"fallback-accepted":"accepted";
    agent.runtime.lastDecisionResponse=normalized.raw;agent.runtime.lastValidation={ok:true,errors:[],tick:state.tick,provider:normalized.provider};
    this.metrics.accepted++;this.count(normalized.provider,"accepted");
    this.memory.trace(agent,"PROVIDER",`${normalized.provider} → ${normalized.action.type} c=${normalized.confidence.toFixed(2)}${isFallback?" [fallback]":""}`);
    this.memory.trace(agent,"VALIDATE",`PASS ${normalized.requestId}`);
  }
  fallbackLocal(state,task,queue,reason){
    this.metrics.fallbacks++;const agent=task.agent;
    const request=this.requestFactory.build(state,agent,task.observation,"local-fallback");agent.runtime.lastDecisionRequest=request;
    const entry=this.registry.get("local");this.metrics.calls++;this.count("local","calls");
    try{
      const response=entry.adapter.decide(request,{agent,observation:task.observation,summary:task.summary,planner:task.context.planner});
      if(response&&typeof response.then==="function")throw new Error("local fallback must be synchronous");
      const checked=this.validator.validate(response,request,state);
      if(checked.ok){this.applyAccepted(state,{...task,request},checked.normalized,queue,true);return}
      this.metrics.invalid++;this.count("local","invalid");agent.runtime.lastValidation={ok:false,errors:checked.errors,tick:state.tick,provider:"local"};
      this.internalWait(state,task,queue,`fallback rejected: ${checked.errors[0]||reason}`);
    }catch(error){this.metrics.providerErrors++;this.count("local","errors");this.internalWait(state,task,queue,`fallback failed: ${error.message}`)}
  }
  complete(state,task,queue){
    if(task.kind==="pending"||task.kind==="pending-started"){
      this.metrics.pendingWaits++;this.internalWait(state,task,queue,`waiting for ${task.providerId} response`);return;
    }
    if(task.kind==="error"){
      this.metrics.providerErrors++;this.count(task.providerId,"errors");task.agent.runtime.lastValidation={ok:false,errors:[task.error.message],tick:state.tick,provider:task.providerId};
      this.memory.trace(task.agent,"VALIDATE",`PROVIDER ERROR · ${task.error.message}`);
      if(state.tick-this.lastWarningTick>24){this.events.emit(state.tick,"PROVIDER_ERROR",`${task.agent.name}: ${task.error.message} → local fallback`,{agentId:task.agent.id,provider:task.providerId},"danger");this.lastWarningTick=state.tick}
      this.fallbackLocal(state,task,queue,task.error.message);return;
    }
    if(finite(task.latencyMs)){this.metrics.latencyTotalMs+=Number(task.latencyMs);this.metrics.latencySamples++}
    const checked=this.validator.validate(task.rawResponse,task.request,state);
    if(checked.ok){this.applyAccepted(state,task,checked.normalized,queue,false);return}
    this.metrics.invalid++;this.count(task.providerId,"invalid");task.agent.runtime.lastDecisionResponse=task.rawResponse;
    task.agent.runtime.lastValidation={ok:false,errors:checked.errors,tick:state.tick,provider:task.providerId};task.agent.runtime.providerStatus="rejected";
    this.memory.trace(task.agent,"VALIDATE",`REJECT · ${checked.errors.join(" | ")}`);
    if(state.tick-this.lastWarningTick>24){this.events.emit(state.tick,"DECISION_REJECTED",`${task.agent.name}: ${checked.errors[0]} → local fallback`,{agentId:task.agent.id,provider:task.providerId},"danger");this.lastWarningTick=state.tick}
    this.fallbackLocal(state,task,queue,checked.errors[0]||"invalid provider response");
  }
  pendingCount(){return this.pending.size}
  averageLatency(){return this.metrics.latencySamples?this.metrics.latencyTotalMs/this.metrics.latencySamples:0}
}

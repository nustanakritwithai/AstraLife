(() => {
  "use strict";

  const VERSION = "p6.1-turn-ahead";
  let lastExecutionTick = null;
  let lastThinkTick = null;
  let lastExecutedCount = 0;
  let lastThinkingCount = 0;

  function captureObservation(agent,{ingest=false,trace=false}={}){
    const observation = runtime.observer.capture(runtime.state, agent);
    const contract = runtime.observationContract.validate(observation);
    agent.runtime.lastObservationContract = contract;
    if(!contract.ok){
      runtime.state.metrics.observationContractErrors++;
      runtime.memory.trace(agent, "OBS", `CONTRACT FAIL · ${contract.errors.join(" | ")}`);
      return {ok:false, observation, errors:contract.errors};
    }
    if(ingest)runtime.memory.ingest(agent, observation, runtime.state);
    if(trace)runtime.memory.trace(agent, "OBS", `${observation.protocol} · resources=${observation.visibleResources.length}, peers=${observation.nearbyAgents.length}, messages=${observation.messages.length}`);
    return {ok:true, observation, errors:[]};
  }

  function harvestReadyForExecution(state, summary){
    const router = runtime.decisionRouter;
    const executionPackets = [];
    const failedPackets = [];

    for(const agent of state.agents){
      if(!agent.alive)continue;
      if(router.ready.has(agent.id)){
        const ready = router.ready.get(agent.id);
        router.ready.delete(agent.id);
        executionPackets.push({agent, ready});
      }
      if(router.failed.has(agent.id)){
        const failure = router.failed.get(agent.id);
        router.failed.delete(agent.id);
        failedPackets.push({agent, failure});
      }
    }

    let executed = 0;
    for(const {agent, ready} of executionPackets){
      if(!agent.alive)continue;
      // Pre-execution observation is validation-only. It is deliberately not
      // ingested into memory; the authoritative memory observation happens
      // after RESOLVE/LEARN, immediately before thinking for the next turn.
      const captured = captureObservation(agent,{ingest:false,trace:false});
      if(!captured.ok){
        runtime.queue.enqueue(state.tick, agent.id, ACTION.WAIT, {}, `invalid execution observation: ${captured.errors[0]}`, {provider:"runtime",validated:true});
        continue;
      }
      const request = ready.request;
      const identityOk = request &&
        request.agent?.id === agent.id &&
        request.sessionId === agent.runtime.providerSessionId &&
        request.simulation?.id === state.simulationId &&
        request.simulation?.tick < state.tick;
      if(!identityOk){
        agent.runtime.providerStatus = "turn-ahead-stale";
        runtime.memory.trace(agent, "VALIDATE", "TURN-AHEAD REJECT · stale/wrong Agent session or same-turn response");
        continue;
      }
      const context = {agent,observation:captured.observation,summary,planner:runtime.planner};
      const task = {
        kind:"response",
        agent,
        observation:captured.observation,
        summary,
        context,
        request,
        providerId:ready.providerId,
        rawResponse:ready.response,
        latencyMs:ready.latencyMs
      };
      const before = runtime.queue.items.length;
      router.complete(state, task, runtime.queue);
      if(runtime.queue.items.length > before)executed++;
    }

    for(const {agent, failure} of failedPackets){
      if(!agent.alive)continue;
      const captured = captureObservation(agent,{ingest:false,trace:false});
      if(!captured.ok)continue;
      const context = {agent,observation:captured.observation,summary,planner:runtime.planner};
      const task = {
        kind:"error",
        agent,
        observation:captured.observation,
        summary,
        context,
        request:failure.request,
        providerId:failure.providerId,
        error:failure.error
      };
      const before = runtime.queue.items.length;
      router.complete(state, task, runtime.queue);
      if(runtime.queue.items.length > before)executed++;
    }
    return executed;
  }

  function startThinkingForNextTurn(state, summary){
    const router = runtime.decisionRouter;
    let thinking = 0;

    for(const agent of state.agents){
      if(!agent.alive)continue;
      const captured = captureObservation(agent,{ingest:true,trace:true});
      if(!captured.ok)continue;

      // One logical decision at a time per Agent. A slow provider is allowed to
      // finish rather than spawning a second overlapping thought request.
      if(router.pending.has(agent.id)){
        agent.runtime.providerStatus = "thinking-next-turn";
        continue;
      }
      if(router.ready.has(agent.id)){
        agent.runtime.providerStatus = "planned-next-turn";
        continue;
      }

      const packet = {agent,observation:captured.observation,planner:runtime.planner};
      const task = router.prepare(state, packet, summary);
      if(task.kind === "pending"){
        agent.runtime.providerStatus = "thinking-next-turn";
        continue;
      }
      if(task.kind === "response"){
        router.ready.set(agent.id, {request:task.request,response:task.rawResponse,providerId:task.providerId,latencyMs:task.latencyMs || 0});
        agent.runtime.providerStatus = "planned-next-turn";
        thinking++;
        continue;
      }
      if(task.kind === "error"){
        router.failed.set(agent.id, {request:task.request,providerId:task.providerId,error:task.error});
        agent.runtime.providerStatus = "plan-error-next-turn";
        thinking++;
        continue;
      }
      if(task.kind !== "request")continue;

      router.invoke(task);
      if(task.kind === "response"){
        router.ready.set(agent.id, {request:task.request,response:task.rawResponse,providerId:task.providerId,latencyMs:task.latencyMs || 0});
        agent.runtime.providerStatus = "planned-next-turn";
      }else if(task.kind === "error"){
        router.failed.set(agent.id, {request:task.request,providerId:task.providerId,error:task.error});
        agent.runtime.providerStatus = "plan-error-next-turn";
      }else{
        agent.runtime.providerStatus = "thinking-next-turn";
      }
      thinking++;
    }
    return thinking;
  }

  runtime.tickOnce = function(){
    const state = this.state;
    state.tick++;
    this.decisionRouter.cleanup(state);

    this.setPhase("ENVIRONMENT",0);
    this.environment.update(state);
    const summary = {alive:state.agents.filter(a=>a.alive).length};

    // TURN N: execute only a decision produced before this turn.
    this.setPhase("VALIDATE",4);
    lastExecutedCount = harvestReadyForExecution(state, summary);

    this.setPhase("RESOLVE",5);
    const actions = this.queue.drain();
    state.metrics.lastActionCount = actions.length;
    state.metrics.totalActions += actions.length;
    const outcomes = this.resolver.resolve(state, actions);

    this.setPhase("LEARN",6);
    for(const outcome of outcomes){
      const agent = state.agentById.get(outcome.agentId);
      if(agent)this.memory.learn(agent,outcome);
      if(!outcome.ok)state.metrics.failedActions++;
    }
    lastExecutionTick = state.tick;

    // After the current turn is resolved, observe the new state and think one
    // full turn ahead. The resulting decision is staged in router.ready and is
    // not allowed to mutate the world until the next authoritative tick.
    this.setPhase("OBSERVE",1);
    this.setPhase("REQUEST",2);
    this.setPhase("PROVIDER",3);
    lastThinkingCount = startThinkingForNextTurn(state, summary);
    lastThinkTick = state.tick;

    this.setPhase("COMMIT",7);
    state.effects.messages = state.effects.messages.filter(e=>state.tick-e.bornTick<15);
    return outcomes;
  };

  window.AstraLifeTurnAhead = Object.freeze({
    version: VERSION,
    policy: "turn N thinks for N+1; turn N+1 executes N while thinking for N+2",
    status: () => ({
      tick:runtime.state.tick,
      lastExecutionTick,
      lastThinkTick,
      lastExecutedCount,
      lastThinkingCount,
      pending:runtime.decisionRouter.pendingCount(),
      ready:runtime.decisionRouter.ready.size,
      failed:runtime.decisionRouter.failed.size
    })
  });
})();

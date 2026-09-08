(() => {
  "use strict";

  const VERSION = "p5.2";
  const SCENARIO_STATES = Object.freeze(["RECRUITING", "IN_PROGRESS", "COMPLETED", "BLOCKED", "CANCELLED"]);
  const clone = value => typeof cloneJson === "function" ? cloneJson(value) : JSON.parse(JSON.stringify(value));
  const now = () => Number(runtime?.state?.tick || 0);
  const result = (ok, error = null, extra = {}) => ({ ok, ...(error ? { error } : {}), ...clone(extra) });
  const getAgent = id => runtime?.state?.agentById?.get(Number(id)) || null;
  const ids = values => [...new Set((values || []).map(Number).filter(Number.isFinite))];
  const p5 = () => window.AstraLifeP5;

  function blankSlice() {
    return { version: VERSION, nextScenario: 1, nextAction: 1, scenarios: new Map(), events: [] };
  }

  function ensureSlice(state) {
    if (!state.cooperativeSlice || state.cooperativeSlice.version !== VERSION) state.cooperativeSlice = blankSlice();
    return state.cooperativeSlice;
  }

  function emit(slice, type, payload = {}) {
    const event = { id: slice.events.length + 1, tick: now(), type, ...clone(payload) };
    slice.events.push(event);
    if (slice.events.length > 200) slice.events.splice(0, slice.events.length - 200);
    if (runtime?.events?.emit) runtime.events.emit(event.tick, `COOP_${type}`, `Cooperative slice: ${type}`, payload, "important");
    return event;
  }

  function scenarioFor(taskId) {
    return ensureSlice(runtime.state).scenarios.get(String(taskId)) || null;
  }

  function acceptedMemberIds(task) {
    const protocol = p5();
    return task.memberIds.filter(agentId => protocol.getCommitment(task.taskId, agentId)?.status === "ACCEPTED");
  }

  function liveAcceptedMemberIds(task) {
    return acceptedMemberIds(task).filter(agentId => getAgent(agentId)?.alive === true);
  }

  function scenarioView(scenario) {
    return clone({
      ...scenario,
      offeredMemberIds: scenario.offeredMemberIds.slice(),
      acceptedMemberIds: scenario.acceptedMemberIds.slice(),
      confirmedContributorIds: scenario.confirmedContributorIds.slice(),
      resolverOutcomeIds: scenario.resolverOutcomeIds.slice(),
      confirmedContributions: scenario.confirmedContributions.slice()
    });
  }

  function createShelterProposal(input = {}) {
    const protocol = p5();
    if (!protocol) return result(false, "P5_PROTOCOL_UNAVAILABLE");
    const proposerId = Number(input.proposerId);
    const proposer = getAgent(proposerId);
    if (!proposer?.alive) return result(false, "PROPOSER_UNAVAILABLE");

    const offeredMemberIds = ids(input.memberIds).filter(agentId => agentId !== proposerId && getAgent(agentId)?.alive);
    const requiredMembers = Math.max(2, Number(input.requiredMembers) || 2);
    if (offeredMemberIds.length + 1 < requiredMembers) return result(false, "NOT_ENOUGH_OFFERED_MEMBERS");

    const taskId = String(input.taskId || `coop-shelter:${runtime.state.simulationId}:${ensureSlice(runtime.state).nextScenario++}`);
    const materialNeeds = { wood: Math.max(Number(CONFIG.buildWoodCost) || 0, Number(input.wood) || Number(CONFIG.buildWoodCost) || 0) };
    const proposal = protocol.proposeTask({
      taskId,
      taskType: "SHELTER_BUILD",
      proposerId,
      memberIds: offeredMemberIds,
      requiredMembers,
      deadlineTick: input.deadlineTick === undefined ? now() + 120 : Number(input.deadlineTick)
    });
    if (!proposal.ok) return result(false, proposal.error, { proposal });

    const scenario = {
      scenarioId: `shelter-slice:${taskId}`,
      taskId,
      type: "SHELTER_BUILD",
      objective: "complete one communal shelter before the deadline",
      proposerId,
      offeredMemberIds,
      requiredMembers,
      materialNeeds,
      state: "RECRUITING",
      createdTick: now(),
      updatedTick: now(),
      baseShelter: Number(runtime.state.camp.shelter) || 0,
      baseWood: Number(runtime.state.stock.wood) || 0,
      acceptedMemberIds: [],
      confirmedContributorIds: [],
      resolverOutcomeIds: [],
      confirmedContributions: [],
      completionEvidence: null,
      teamBonus: 0,
      bonusApplied: false,
      lastReason: "proposal created"
    };
    ensureSlice(runtime.state).scenarios.set(taskId, scenario);
    emit(ensureSlice(runtime.state), "PROPOSAL_CREATED", { taskId, proposerId, offeredMemberIds, requiredMembers, materialNeeds });
    return result(true, null, { scenario: scenarioView(scenario), proposal });
  }

  function refreshScenario(scenario) {
    const task = p5().getTask(scenario.taskId);
    if (!task) return result(false, "TEAM_TASK_NOT_FOUND");
    scenario.acceptedMemberIds = acceptedMemberIds(task);
    scenario.updatedTick = now();
    if (scenario.state === "COMPLETED" || scenario.state === "CANCELLED") return result(true, null, { scenario: scenarioView(scenario), task });
    if (task.state === "IN_PROGRESS") scenario.state = "IN_PROGRESS";
    else if (task.state === "READY" || task.state === "RECRUITING" || task.state === "PROPOSED") scenario.state = "RECRUITING";
    else scenario.state = "BLOCKED";
    return result(true, null, { scenario: scenarioView(scenario), task });
  }

  function startShelter(taskId) {
    const scenario = scenarioFor(taskId);
    if (!scenario) return result(false, "SCENARIO_NOT_FOUND");
    const task = p5().getTask(taskId);
    if (!task) return result(false, "TEAM_TASK_NOT_FOUND");
    if (task.state !== "READY") return result(false, "EXPLICIT_COMMITMENTS_INCOMPLETE", { task, scenario: scenarioView(scenario) });
    const liveAccepted = liveAcceptedMemberIds(task);
    if (liveAccepted.length < scenario.requiredMembers) return result(false, "LIVE_COMMITTED_MEMBERS_INCOMPLETE", { task, liveAccepted });
    if (Number(runtime.state.stock.wood) < scenario.materialNeeds.wood) {
      scenario.state = "BLOCKED";
      scenario.lastReason = "world constraint: insufficient wood for shelter";
      return result(false, "INSUFFICIENT_SHELTER_MATERIAL", { task, scenario: scenarioView(scenario), requiredWood: scenario.materialNeeds.wood, availableWood: runtime.state.stock.wood });
    }
    const started = p5().startTask(taskId);
    if (!started.ok) return result(false, started.error, { started });
    scenario.state = "IN_PROGRESS";
    scenario.acceptedMemberIds = acceptedMemberIds(task);
    scenario.lastReason = "explicit commitments satisfied; resolver execution unlocked";
    emit(ensureSlice(runtime.state), "STARTED", { taskId, acceptedMemberIds: scenario.acceptedMemberIds, requiredMembers: scenario.requiredMembers });
    return result(true, null, { scenario: scenarioView(scenario), task: p5().getTask(taskId) });
  }

  function performResolverActions(taskId, actionInputs = []) {
    const scenario = scenarioFor(taskId);
    const protocol = p5();
    const task = protocol?.getTask(taskId);
    if (!scenario || !task) return result(false, "SCENARIO_NOT_FOUND");
    if (task.state !== "IN_PROGRESS" || scenario.state !== "IN_PROGRESS") return result(false, "SCENARIO_NOT_IN_PROGRESS", { task, scenario: scenarioView(scenario) });

    const requests = Array.isArray(actionInputs) ? actionInputs : [];
    const requestedIds = ids(requests.map(input => input.agentId));
    if (requestedIds.length < scenario.requiredMembers) return result(false, "COOPERATIVE_MEMBER_SET_INCOMPLETE", { requiredMembers: scenario.requiredMembers, requestedIds });
    if (requestedIds.length !== requests.length) return result(false, "DUPLICATE_COOPERATIVE_ACTOR");
    const accepted = new Set(liveAcceptedMemberIds(task));
    for (const agentId of requestedIds) {
      if (!accepted.has(agentId)) return result(false, "ACTOR_NOT_EXPLICITLY_COMMITTED", { agentId, acceptedMemberIds: [...accepted] });
      const agent = getAgent(agentId);
      if (!agent || distance(agent.body, runtime.state.camp) > 45) return result(false, "ACTOR_OUTSIDE_SHELTER_ZONE", { agentId });
    }
    for (const input of requests) {
      if (input.type && input.type !== ACTION.BUILD) return result(false, "COOPERATIVE_ACTION_TYPE_NOT_ALLOWED", { type: input.type });
    }

    const actions = requests.map(input => ({
      id: `coop-action:${scenario.scenarioId}:${ensureSlice(runtime.state).nextAction++}`,
      tick: now(),
      agentId: Number(input.agentId),
      type: input.type || ACTION.BUILD,
      payload: { ...(input.payload || {}) },
      reason: "P5.2 explicit cooperative commitment",
      priority: PRIORITY.BUILD,
      meta: { validated: true, provider: "p5.2-cooperative-slice", teamTaskId: taskId }
    }));
    const beforeShelter = Number(runtime.state.camp.shelter) || 0;
    const beforeWood = Number(runtime.state.stock.wood) || 0;
    const goalsBefore = new Map(requestedIds.map(agentId => [agentId, getAgent(agentId)?.mind?.goal]));
    const outcomes = runtime.resolver.resolve(runtime.state, actions);
    const confirmed = [];

    for (const outcome of outcomes) {
      const agent = getAgent(outcome.agentId);
      if (agent) runtime.memory.learn(agent, outcome);
      const action = actions.find(candidate => candidate.id === outcome.actionId);
      if (!outcome.ok || !action || action.type !== ACTION.BUILD) continue;
      const contribution = protocol.recordContribution({
        taskId,
        agentId: outcome.agentId,
        actionId: outcome.actionId,
        actionType: outcome.actionType,
        amount: 1
      });
      if (!contribution.ok) return result(false, "CONTRIBUTION_RECORD_FAILED", { contribution, outcomes });
      if (!scenario.confirmedContributorIds.includes(outcome.agentId)) scenario.confirmedContributorIds.push(outcome.agentId);
      scenario.resolverOutcomeIds.push(outcome.actionId);
      scenario.confirmedContributions.push({
        actionId: outcome.actionId,
        agentId: outcome.agentId,
        actionType: outcome.actionType,
        resolverConfirmed: true,
        tick: now(),
        contributionId: contribution.contribution.contributionId
      });
      confirmed.push({ outcome: clone(outcome), contribution: clone(contribution.contribution) });
    }

    const goalChanges = requestedIds.filter(agentId => getAgent(agentId)?.mind?.goal !== goalsBefore.get(agentId));
    const shelterDelta = (Number(runtime.state.camp.shelter) || 0) - beforeShelter;
    scenario.updatedTick = now();
    scenario.acceptedMemberIds = acceptedMemberIds(task);
    scenario.lastReason = confirmed.length ? "resolver-confirmed member contribution" : "resolver rejected all cooperative actions";

    if (shelterDelta > 0) {
      if (scenario.confirmedContributorIds.length < scenario.requiredMembers) {
        scenario.state = "BLOCKED";
        scenario.lastReason = "shelter changed without enough distinct resolver-confirmed contributors";
        return result(false, "INSUFFICIENT_CONFIRMED_CONTRIBUTORS", { outcomes, confirmed, scenario: scenarioView(scenario) });
      }
      const completed = protocol.completeTask(taskId);
      if (!completed.ok) return result(false, "TEAM_TASK_COMPLETION_FAILED", { completed, outcomes, confirmed });
      scenario.state = "COMPLETED";
      scenario.completionEvidence = {
        resolverConfirmed: true,
        resolverOutcomeIds: scenario.resolverOutcomeIds.slice(),
        contributorIds: scenario.confirmedContributorIds.slice(),
        shelterBefore: scenario.baseShelter,
        shelterAfter: Number(runtime.state.camp.shelter) || 0,
        shelterDelta: (Number(runtime.state.camp.shelter) || 0) - scenario.baseShelter,
        woodBefore: scenario.baseWood,
        woodAfter: Number(runtime.state.stock.wood) || 0,
        materialConsumed: scenario.baseWood - (Number(runtime.state.stock.wood) || 0),
        noHiddenTeamBonus: scenario.teamBonus === 0 && scenario.bonusApplied === false,
        goalChanges
      };
      scenario.lastReason = "shelter completed by resolver-confirmed committed members";
      emit(ensureSlice(runtime.state), "COMPLETED", { taskId, contributorIds: scenario.confirmedContributorIds, shelterDelta: scenario.completionEvidence.shelterDelta });
    }
    return result(true, null, { outcomes: outcomes.map(clone), confirmed, scenario: scenarioView(scenario), goalChanges, shelterDelta, woodBefore: beforeWood, woodAfter: Number(runtime.state.stock.wood) || 0 });
  }

  function runCommittedShelter(taskId, participantIds, options = {}) {
    const scenario = scenarioFor(taskId);
    if (!scenario) return result(false, "SCENARIO_NOT_FOUND");
    const participants = ids(participantIds);
    const maxRounds = Math.max(1, Math.min(Number(options.maxRounds) || 100, 250));
    const rounds = [];
    for (let i = 0; i < maxRounds; i++) {
      const current = p5().getTask(taskId);
      if (!current || current.state === "COMPLETED") break;
      if (current.deadlineTick !== null && now() > current.deadlineTick) {
        p5().expire(current.deadlineTick + 1);
        return result(false, "COOPERATIVE_DEADLINE_EXPIRED", { rounds, task: p5().getTask(taskId), scenario: scenarioView(scenario) });
      }
      if (current.state !== "IN_PROGRESS") return result(false, "TEAM_STOPPED_BEFORE_COMPLETION", { rounds, task: current, scenario: scenarioView(scenario) });
      const live = participants.filter(agentId => getAgent(agentId)?.alive);
      if (live.length < scenario.requiredMembers) {
        p5().markUnavailable(participants.find(agentId => !getAgent(agentId)?.alive), "cooperative member unavailable");
        return result(false, "COOPERATIVE_MEMBER_UNAVAILABLE", { rounds, task: p5().getTask(taskId), scenario: scenarioView(scenario) });
      }
      const step = performResolverActions(taskId, live.map(agentId => ({ agentId, type: ACTION.BUILD, payload: {} })));
      rounds.push(step);
      if (!step.ok) return result(false, step.error || "COOPERATIVE_STEP_FAILED", { rounds, task: p5().getTask(taskId), scenario: scenarioView(scenario) });
      if (step.scenario?.state === "COMPLETED") return result(true, null, { rounds, task: p5().getTask(taskId), scenario: step.scenario });
    }
    const finalScenario = scenarioView(scenario);
    return result(finalScenario.state === "COMPLETED", finalScenario.state === "COMPLETED" ? null : "SHELTER_COMPLETION_TIMEOUT", { rounds, task: p5().getTask(taskId), scenario: finalScenario });
  }

  function serialise(slice) {
    return { version: VERSION, scenarios: [...slice.scenarios.values()].map(scenarioView), events: slice.events.slice(-100).map(clone) };
  }

  function integrity(state = runtime.state) {
    const slice = ensureSlice(state);
    const taskState = taskId => state.teamProtocol?.tasks instanceof Map ? state.teamProtocol.tasks.get(String(taskId))?.state : null;
    const errors = [];
    for (const scenario of slice.scenarios.values()) {
      if (!SCENARIO_STATES.includes(scenario.state)) errors.push(`scenario ${scenario.taskId} invalid state`);
      if (scenario.teamBonus !== 0 || scenario.bonusApplied !== false) errors.push(`scenario ${scenario.taskId} hidden team bonus`);
      for (const agentId of scenario.confirmedContributorIds) {
        if (!scenario.confirmedContributions.some(contribution => contribution.agentId === agentId && contribution.resolverConfirmed === true)) errors.push(`scenario ${scenario.taskId} contribution without resolver evidence`);
      }
      if (scenario.state === "COMPLETED" && !scenario.completionEvidence?.resolverConfirmed) errors.push(`scenario ${scenario.taskId} missing completion evidence`);
      if (scenario.state === "COMPLETED" && taskState(scenario.taskId) !== "COMPLETED") errors.push(`scenario ${scenario.taskId} task not completed`);
    }
    return { ok: errors.length === 0, errors };
  }

  const oldReset = WorldRuntime.prototype.reset;
  WorldRuntime.prototype.reset = function(seed = this.seed) {
    const output = oldReset.call(this, seed);
    this.state.cooperativeSlice = blankSlice();
    return output;
  };
  const oldSnapshot = WorldRuntime.prototype.snapshot;
  WorldRuntime.prototype.snapshot = function() {
    const snapshot = oldSnapshot.call(this);
    snapshot.cooperativeSlice = serialise(ensureSlice(this.state));
    return snapshot;
  };
  const oldSelfTest = WorldRuntime.prototype.selfTest;
  WorldRuntime.prototype.selfTest = function() {
    const base = oldSelfTest.call(this);
    const slice = integrity(this.state);
    return { ok: base.ok && slice.ok, errors: [...base.errors, ...slice.errors] };
  };

  ensureSlice(runtime.state);
  window.AstraLifeP52 = Object.freeze({
    version: VERSION,
    scenarioStates: SCENARIO_STATES.slice(),
    createShelterProposal,
    refreshScenario,
    startShelter,
    performResolverActions,
    runCommittedShelter,
    getScenario: taskId => { const scenario = scenarioFor(taskId); return scenario ? scenarioView(scenario) : null; },
    snapshot: () => serialise(ensureSlice(runtime.state)),
    selfTest: integrity
  });
})();

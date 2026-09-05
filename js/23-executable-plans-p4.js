(() => {
  "use strict";

  const VERSION = "p4.0";
  const MAX_REPLANS = 3;
  const MAX_RETRIES_PER_STEP = 2;
  const DEFAULT_TIMEOUT_TICKS = 45;
  const PLAN_WINDOW_TICKS = 180;
  const TERMINAL = new Set(["COMPLETED", "INVALIDATED", "ABORTED", "TIMEOUT"]);
  const VALID_ON_FAILURE = new Set(["REPLAN", "RETRY_BOUNDED", "ABORT"]);

  const carryFor = type => ({water:"water", berry:"food", tree:"wood", herb:"medicine"}[type] || null);
  const sig = action => `${action?.type || "WAIT"}:${JSON.stringify(action?.payload || {})}`;
  const stepById = (plan, id) => (plan.steps || []).find(s => s.stepId === id) || null;
  const currentStep = plan => stepById(plan, plan.currentStepId);
  const nowTick = () => runtime?.state?.tick ?? 0;
  const planTrace = (agent, text) => runtime?.memory?.trace(agent, "PLAN", text);

  function normalizeBudget(agent, tick){
    const old = agent.mind.planBudget;
    if(!old || tick - Number(old.windowStartTick || 0) > PLAN_WINDOW_TICKS){
      agent.mind.planBudget = {windowStartTick: tick, replanCount: 0, retryCount: 0};
    }else{
      agent.mind.planBudget = {windowStartTick: old.windowStartTick, replanCount: Number(old.replanCount || 0), retryCount: Number(old.retryCount || 0)};
    }
    return agent.mind.planBudget;
  }

  function ensure(agent){
    if(!agent.mind.executablePlan || agent.mind.executablePlan.version !== VERSION){
      agent.mind.executablePlan = {
        version: VERSION,
        planId: `plan:${agent.id}:bootstrap`,
        goal: agent.mind.goal || "orient",
        status: "EMPTY",
        steps: [],
        currentStepId: null,
        createdTick: nowTick(),
        updatedTick: nowTick(),
        replanCount: 0,
        maxReplans: MAX_REPLANS,
        maxRetriesPerStep: MAX_RETRIES_PER_STEP,
        lastFailureReason: null,
        invalidatedActionFingerprints: []
      };
    }
    normalizeBudget(agent, nowTick());
    return agent.mind.executablePlan;
  }

  function targetFromAction(action){
    const p = action.payload || {};
    switch(action.type){
      case ACTION.MOVE: return {kind:"point", x:Number(p.x), y:Number(p.y)};
      case ACTION.GATHER: return {kind:"resource", resourceId:p.resourceId, resourceType:p.resourceType};
      case ACTION.HEAL: return {kind:"agent", targetAgentId:p.targetAgentId};
      case ACTION.CONSUME: return {kind:"supply", resource:p.resource};
      case ACTION.DEPOSIT: return {kind:"camp-stock"};
      case ACTION.BUILD: return {kind:"camp-construction"};
      case ACTION.SHARE: return {kind:"social", targetAgentId:p.targetAgentId || null, intent:p.intent || "SYNC"};
      case ACTION.REST: return {kind:"recovery"};
      case ACTION.WAIT: default: return {kind:"wait"};
    }
  }

  function preconditionsFor(action){
    const p = action.payload || {};
    switch(action.type){
      case ACTION.MOVE: return [{kind:"bounds", minX:4, maxX:SPACE.width-4, minY:4, maxY:SPACE.height-4}];
      case ACTION.GATHER: return [{kind:"observable-resource", resourceId:p.resourceId, resourceType:p.resourceType}, {kind:"interaction-range", range:CONFIG.interactRange+2}, {kind:"inventory-compatible", carryType:p.carryType}];
      case ACTION.DEPOSIT: return [{kind:"camp-visible"}, {kind:"camp-sync-range", range:CONFIG.campSyncRange}, {kind:"inventory-not-empty"}];
      case ACTION.CONSUME: return [{kind:"supply-reachable", resource:p.resource}];
      case ACTION.BUILD: return [{kind:"camp-visible"}, {kind:"builder-role"}, {kind:"construction-zone", range:45}];
      case ACTION.HEAL: return [{kind:"healer-role"}, {kind:"visible-target-agent", targetAgentId:p.targetAgentId}, {kind:"interaction-range", range:CONFIG.interactRange+5}];
      case ACTION.SHARE: return [{kind:"communication-range-or-broadcast"}, {kind:"safe-structured-message"}];
      case ACTION.REST: return [{kind:"alive-agent"}];
      case ACTION.WAIT: default: return [{kind:"runtime-safe"}];
    }
  }

  function successFor(action){
    switch(action.type){
      case ACTION.MOVE: return {kind:"reached-target-or-progress"};
      case ACTION.GATHER: return {kind:"inventory-increased-or-full"};
      case ACTION.DEPOSIT: return {kind:"cargo-committed-to-stock"};
      case ACTION.CONSUME: return {kind:"need-reduced"};
      case ACTION.BUILD: return {kind:"construction-progress-confirmed"};
      case ACTION.HEAL: return {kind:"target-hp-increased"};
      case ACTION.SHARE: return {kind:"message-delivered"};
      case ACTION.REST: return {kind:"energy-recovered"};
      case ACTION.WAIT: default: return {kind:"safe-noop"};
    }
  }

  function makeStep(state, agent, normalized, source="provider"){
    const action = cloneJson(normalized.action || {type:ACTION.WAIT, payload:{}});
    const timeout = state.tick + DEFAULT_TIMEOUT_TICKS + Math.max(0, Number(normalized.replanAfterTicks || 1));
    const step = {
      stepId: `step:${state.simulationId}:${state.tick}:${agent.id}:${Math.abs(hashSeed(`${normalized.requestId}|${sig(action)}`)).toString(16)}`,
      actionType: action.type,
      action,
      target: targetFromAction(action),
      preconditions: preconditionsFor(action),
      successCondition: successFor(action),
      timeoutTick: timeout,
      onFailure: action.type === ACTION.WAIT ? "ABORT" : "REPLAN",
      status: "PENDING",
      attemptCount: 0,
      createdTick: state.tick,
      lastValidatedTick: null,
      source,
      requestId: normalized.requestId || null,
      sourceTick: normalized.sourceTick,
      provider: normalized.provider || "unknown",
      confidence: clamp(Number(normalized.confidence ?? .5), 0, 1),
      lastFailureReason: null,
      actionFingerprint: sig(action)
    };
    if(!VALID_ON_FAILURE.has(step.onFailure))step.onFailure = "ABORT";
    return step;
  }

  function createPlan(state, agent, normalized, source="provider"){
    const budget = normalizeBudget(agent, state.tick);
    const step = makeStep(state, agent, normalized, source);
    const plan = ensure(agent);
    plan.planId = `plan:${state.simulationId}:${state.tick}:${agent.id}:${Math.abs(hashSeed(`${normalized.requestId}|${step.stepId}`)).toString(16)}`;
    plan.goal = String(normalized.cognition?.goal || agent.mind.goal || "orient").slice(0,80);
    plan.status = "ACTIVE";
    plan.steps = [step];
    plan.currentStepId = step.stepId;
    plan.createdTick = state.tick;
    plan.updatedTick = state.tick;
    plan.replanCount = budget.replanCount;
    plan.maxReplans = MAX_REPLANS;
    plan.maxRetriesPerStep = MAX_RETRIES_PER_STEP;
    plan.lastFailureReason = null;
    planTrace(agent, `P4 created ${step.actionType} step ${step.stepId}`);
    return plan;
  }

  function resourceVisible(obs, id){
    return (obs.visibleResources || []).find(r => r.id === id) || null;
  }
  function peerVisible(obs, id){
    return (obs.nearbyAgents || []).find(p => p.id === id) || null;
  }

  function validateStep(agent, observation, state, step){
    const errors = [];
    const need = (ok, msg) => { if(!ok)errors.push(msg); };
    if(!step || !isPlainObject(step))return {ok:false, errors:["missing executable step"]};
    if(TERMINAL.has(step.status))return {ok:false, errors:[`step is terminal: ${step.status}`]};
    need(step.timeoutTick >= state.tick, "step timeout exceeded");
    need(step.attemptCount <= MAX_RETRIES_PER_STEP, "step retry budget exceeded");
    need(Object.values(ACTION).includes(step.actionType), "unknown runtime action enum");
    const action = step.action || {type:step.actionType, payload:{}};
    need(action.type === step.actionType, "step action/type mismatch");
    need(sig(action) === step.actionFingerprint, "step payload fingerprint changed");

    switch(step.actionType){
      case ACTION.MOVE:{
        const t = step.target || {}; need(finite(t.x) && finite(t.y), "MOVE target is not finite");
        need(Number(t.x) >= 4 && Number(t.x) <= SPACE.width-4 && Number(t.y) >= 4 && Number(t.y) <= SPACE.height-4, "MOVE target outside world bounds");
        break;
      }
      case ACTION.GATHER:{
        const p = action.payload || {}, r = resourceVisible(observation, p.resourceId);
        need(!!r, "target resource is no longer observable");
        if(r){ need(r.type === p.resourceType, "target resource type changed"); need(r.distance <= CONFIG.interactRange + 2, "target resource outside interaction range"); }
        need(carryFor(p.resourceType) === p.carryType, "resource/carry mapping invalid");
        need(agent.inventory.amount <= .01 || agent.inventory.type === p.carryType, "inventory contains incompatible cargo");
        need(agent.inventory.amount < agent.capacity - .05, "inventory already full");
        break;
      }
      case ACTION.DEPOSIT:
        need(observation.camp.visible, "camp is not observable/reachable");
        need(observation.camp.distance <= CONFIG.campSyncRange, "camp outside deposit range");
        need(!!agent.inventory.type && agent.inventory.amount > .01, "inventory empty");
        break;
      case ACTION.CONSUME:{
        const resource = action.payload?.resource, inventoryType = resource === "water" ? "water" : "food";
        const carried = agent.inventory.type === inventoryType && agent.inventory.amount >= 1;
        const stocked = observation.camp.visible && observation.camp.stock && observation.camp.stock[inventoryType] >= 1;
        need(resource === "water" || resource === "food", "consume resource invalid");
        need(carried || stocked, `no observable reachable ${inventoryType}`);
        break;
      }
      case ACTION.BUILD:
        need(agent.role === "builder", "only builders can build");
        need(observation.camp.visible, "camp not observable for construction");
        need(observation.camp.distance <= 45, "outside construction zone");
        break;
      case ACTION.HEAL:{
        need(agent.role === "healer", "only healers can heal");
        const p = peerVisible(observation, action.payload?.targetAgentId);
        need(!!p, "patient no longer visible");
        if(p)need(p.distance <= CONFIG.interactRange + 5, "patient outside interaction range");
        break;
      }
      case ACTION.SHARE:
        need(SOCIAL_INTENTS.includes(action.payload?.intent), "share intent invalid");
        if(action.payload?.targetAgentId)need(!!peerVisible(observation, action.payload.targetAgentId), "target peer no longer visible");
        break;
      case ACTION.REST:case ACTION.WAIT:
        need(agent.alive, "agent unavailable");
        break;
      default:
        need(false, `unsupported action ${step.actionType}`);
    }
    return {ok:errors.length === 0, errors:errors.slice(0,12)};
  }

  function invalidate(agent, step, reason, state){
    const plan = ensure(agent), budget = normalizeBudget(agent, state.tick);
    step.status = state.tick > step.timeoutTick ? "TIMEOUT" : "INVALIDATED";
    step.lastFailureReason = reason;
    step.lastValidatedTick = state.tick;
    plan.status = budget.replanCount >= MAX_REPLANS ? "ABORTED" : "REPLAN_REQUESTED";
    plan.updatedTick = state.tick;
    plan.lastFailureReason = reason;
    plan.invalidatedActionFingerprints.push({tick:state.tick, stepId:step.stepId, fingerprint:step.actionFingerprint, reason});
    if(plan.invalidatedActionFingerprints.length > 16)plan.invalidatedActionFingerprints.shift();
    if(step.actionType === ACTION.GATHER && step.target?.resourceId){
      agent.mind.facts.delete(`resource:${step.target.resourceId}`);
      agent.mind.target = null;
    }
    if(plan.status === "REPLAN_REQUESTED"){
      budget.replanCount++; plan.replanCount = budget.replanCount; agent.mind.replanAtTick = state.tick;
    }else{
      agent.mind.replanAtTick = state.tick + 18;
    }
    planTrace(agent, `P4 ${step.status}: ${reason}`);
    runtime.memory.remember(agent, `plan step ${step.status.toLowerCase()}: ${reason}`, "learning", {lesson:"revalidate executable plan steps before acting", context:{kind:"p4-plan", stepId:step.stepId, actionType:step.actionType}});
    return plan.status;
  }

  function markOutcome(agent, outcome){
    if(!outcome || !outcome.p4StepId)return;
    const plan = ensure(agent), step = stepById(plan, outcome.p4StepId);
    if(!step)return;
    plan.updatedTick = nowTick();
    if(outcome.ok){
      if(outcome.actionType !== ACTION.MOVE || outcome.reached){
        step.status = "COMPLETED"; plan.status = "COMPLETED"; planTrace(agent, `P4 completed ${step.actionType}`);
      }else{
        step.status = "PENDING"; plan.status = "ACTIVE";
      }
    }else{
      const status = invalidate(agent, step, outcome.message || "resolver rejected step", runtime.state);
      if(status === "REPLAN_REQUESTED" && step.onFailure === "RETRY_BOUNDED" && step.attemptCount < MAX_RETRIES_PER_STEP){
        step.status = "PENDING"; plan.status = "ACTIVE";
      }
    }
  }

  function applyExecutable(state, task, normalized, queue, isFallback, router){
    const agent = task.agent, observation = task.observation;
    agent.mind.goal = normalized.cognition.goal;
    agent.mind.goalReason = normalized.cognition.reason;
    agent.mind.plan = normalized.cognition.plan;
    agent.mind.replanAtTick = state.tick + normalized.replanAfterTicks;
    if(normalized.action.type === ACTION.MOVE)agent.mind.target = {x:normalized.action.payload.x, y:normalized.action.payload.y};

    const plan = ensure(agent);
    let step = currentStep(plan);
    const incomingSig = sig(normalized.action);
    if(!step || TERMINAL.has(step.status) || step.actionFingerprint !== incomingSig || step.requestId !== normalized.requestId){
      createPlan(state, agent, normalized, isFallback ? "fallback" : "provider");
      step = currentStep(ensure(agent));
    }
    const checked = validateStep(agent, observation, state, step);
    agent.runtime.lastDecisionResponse = normalized.raw;
    if(!checked.ok){
      const reason = checked.errors[0] || "plan precondition failed";
      invalidate(agent, step, reason, state);
      queue.enqueue(state.tick, agent.id, ACTION.WAIT, {}, `P4 blocked stale/invalid step: ${reason}`, {provider:"p4-plan", requestId:normalized.requestId, sourceTick:normalized.sourceTick, validated:true, p4PlanId:plan.planId, p4StepId:step.stepId, fallback:isFallback});
      agent.runtime.lastActionType = ACTION.WAIT;
      agent.runtime.lastProvider = normalized.provider;
      agent.runtime.providerStatus = "plan-revalidation-blocked";
      agent.runtime.lastValidation = {ok:false, errors:checked.errors, tick:state.tick, provider:normalized.provider, phase:"p4-plan"};
      router.metrics.invalid++; router.count(normalized.provider, "invalid");
      router.memory.trace(agent, "VALIDATE", `P4 REJECT · ${checked.errors.join(" | ")}`);
      return;
    }

    step.status = "EXECUTING";
    step.lastValidatedTick = state.tick;
    step.attemptCount++;
    plan.status = "ACTIVE";
    plan.updatedTick = state.tick;
    queue.enqueue(state.tick, agent.id, normalized.action.type, normalized.action.payload, normalized.reason, {provider:normalized.provider, requestId:normalized.requestId, sourceTick:normalized.sourceTick, confidence:normalized.confidence, validated:true, fallback:isFallback, p4PlanId:plan.planId, p4StepId:step.stepId});
    agent.runtime.lastActionType = normalized.action.type;
    agent.runtime.lastProvider = normalized.provider;
    agent.runtime.providerStatus = isFallback ? "fallback-plan-accepted" : "plan-accepted";
    agent.runtime.lastValidation = {ok:true, errors:[], tick:state.tick, provider:normalized.provider, phase:"p4-plan"};
    router.metrics.accepted++; router.count(normalized.provider, "accepted");
    router.memory.trace(agent, "PROVIDER", `${normalized.provider} → P4 ${normalized.action.type} step=${step.stepId}${isFallback ? " [fallback]" : ""}`);
    router.memory.trace(agent, "VALIDATE", `P4 PASS ${normalized.requestId}`);
  }

  const oldApplyAccepted = DecisionRouter.prototype.applyAccepted;
  DecisionRouter.prototype.applyAccepted = function(state, task, normalized, queue, isFallback=false){
    return applyExecutable(state, task, normalized, queue, isFallback, this);
  };
  DecisionRouter.prototype.applyAcceptedV03 = oldApplyAccepted;

  const oldLearn = MemorySystem.prototype.learn;
  MemorySystem.prototype.learn = function(agent, outcome){
    const result = oldLearn.call(this, agent, outcome);
    markOutcome(agent, outcome);
    return result;
  };

  const oldResolve = ActionResolver.prototype.outcome;
  ActionResolver.prototype.outcome = function(action, ok, message, significant=false, extra={}){
    return oldResolve.call(this, action, ok, message, significant, {...extra, p4PlanId:action.meta?.p4PlanId || null, p4StepId:action.meta?.p4StepId || null});
  };

  const oldPersistent = AgentStateBoundaryV051.persistent;
  AgentStateBoundaryV051.persistent = function(agent){
    ensure(agent);
    const base = cloneJson(oldPersistent.call(this, agent));
    base.executablePlan = cloneJson(agent.mind.executablePlan);
    base.planBudget = cloneJson(agent.mind.planBudget);
    base.executablePlanSchemaVersion = VERSION;
    return deepFreeze(base);
  };

  if(window.AstraLifeP2?.restorePersistent){
    const p2 = window.AstraLifeP2, oldRestore = p2.restorePersistent;
    window.AstraLifeP2 = Object.freeze({...p2, restorePersistent:(id, snapshot) => {
      const result = oldRestore(id, snapshot);
      if(result?.ok){
        const agent = runtime.state.agentById.get(Number(id));
        if(agent && snapshot?.executablePlan)agent.mind.executablePlan = cloneJson(snapshot.executablePlan);
        if(agent && snapshot?.planBudget)agent.mind.planBudget = cloneJson(snapshot.planBudget);
        if(agent)ensure(agent);
      }
      return result;
    }});
  }

  const oldInspector = window.updateInspector;
  if(typeof oldInspector === "function")window.updateInspector = function(){
    oldInspector();
    const agent = runtime.selectedAgentId ? runtime.state.agentById.get(runtime.selectedAgentId) : null;
    if(!agent || !ui.iwm)return;
    const plan = ensure(agent), step = currentStep(plan);
    ui.iwm.textContent += `\n\n[P4 executable plan]\n${plan.status} · goal=${plan.goal}\nreplans=${plan.replanCount}/${plan.maxReplans}\n${step ? `${step.actionType} · ${step.status} · attempts=${step.attemptCount}/${plan.maxRetriesPerStep}\ntimeout=${step.timeoutTick}\nfailure=${step.lastFailureReason || plan.lastFailureReason || "-"}` : "(no current step)"}`;
  };

  for(const agent of runtime.state.agents)ensure(agent);
  window.AstraLifeP4 = Object.freeze({
    version: VERSION,
    limits: Object.freeze({maxReplans:MAX_REPLANS, maxRetriesPerStep:MAX_RETRIES_PER_STEP, defaultTimeoutTicks:DEFAULT_TIMEOUT_TICKS}),
    ensure: id => {const agent = runtime.state.agentById.get(Number(id)); return agent ? cloneJson(ensure(agent)) : null;},
    currentStep: id => {const agent = runtime.state.agentById.get(Number(id)); if(!agent)return null; return cloneJson(currentStep(ensure(agent)));},
    validateCurrent: (id, observation=null) => {const agent = runtime.state.agentById.get(Number(id)); if(!agent)return {ok:false, errors:["agent not found"]}; const obs = observation || agent.runtime.lastObservation || runtime.observer.capture(runtime.state, agent); return cloneJson(validateStep(agent, obs, runtime.state, currentStep(ensure(agent))));},
    createStepPreview: (id, action) => {const agent = runtime.state.agentById.get(Number(id)); if(!agent)return null; return cloneJson(makeStep(runtime.state, agent, {action, cognition:{goal:agent.mind.goal}, requestId:`preview:${runtime.state.tick}:${agent.id}`, sourceTick:runtime.state.tick, provider:"preview", confidence:.5, replanAfterTicks:1}, "preview"));}
  });
})();
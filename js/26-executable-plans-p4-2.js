(() => {
  "use strict";

  const VERSION = "p4.2";
  const MAX_REPLANS = 3;
  const MAX_RETRIES_PER_STEP = 2;
  const TERMINAL = new Set(["COMPLETED","INVALIDATED","ABORTED","TIMEOUT"]);
  const sig = action => `${action?.type || "WAIT"}:${JSON.stringify(action?.payload || {})}`;
  const agentFor = id => runtime.state.agentById.get(Number(id));
  const planFor = agent => agent?.mind?.executablePlan?.hardeningVersion === VERSION ? agent.mind.executablePlan : null;
  const stepFor = (plan, id) => (plan?.steps || []).find(step => step.stepId === id) || null;
  const current = plan => plan?.currentStepId ? stepFor(plan, plan.currentStepId) : null;
  const now = () => runtime.state.tick;
  const copy = value => cloneJson(value);
  const trace = (agent, text) => runtime.memory.trace(agent, "PLAN", text);

  function normaliseStep(state, agent, spec, index, planId){
    const action = copy(spec?.action || {type:ACTION.WAIT, payload:{}});
    const timeoutTicks = Math.max(1, Math.floor(Number(spec?.timeoutTicks ?? 45)));
    const onFailure = ["REPLAN","RETRY_BOUNDED","ABORT"].includes(spec?.onFailure) ? spec.onFailure : "REPLAN";
    return {
      stepId: `p42-step:${state.simulationId}:${state.tick}:${agent.id}:${index}:${Math.abs(hashSeed(`${planId}|${index}|${sig(action)}`)).toString(16)}`,
      actionType: action.type,
      action,
      target: copy(spec?.target || null),
      preconditions: copy(spec?.preconditions || []),
      successCondition: copy(spec?.successCondition || {kind:"resolver-confirmed-outcome"}),
      timeoutTick: state.tick + timeoutTicks,
      onFailure,
      status: "PENDING",
      attemptCount: 0,
      retryCount: 0,
      createdTick: state.tick,
      lastValidatedTick: null,
      lastFailureReason: null,
      lastFailureClass: null,
      prediction: copy(spec?.prediction || null),
      assumptions: Array.isArray(spec?.assumptions) ? copy(spec.assumptions).slice(0,12) : [],
      predictionStatus: spec?.prediction ? "PENDING" : "NONE",
      outcome: null,
      actionFingerprint: sig(action)
    };
  }

  function validate(agent, step, observation, state){
    const errors = [];
    const need = (ok, message) => { if(!ok) errors.push(message); };
    if(!step){ return {ok:false, errors:["missing current P4.2 step"]}; }
    if(TERMINAL.has(step.status))return {ok:false, errors:[`step is terminal: ${step.status}`]};
    need(state.tick <= step.timeoutTick, "step timeout exceeded");
    need(step.retryCount <= MAX_RETRIES_PER_STEP, "step retry budget exceeded");
    need(Object.values(ACTION).includes(step.actionType), "unknown runtime action enum");
    need(sig(step.action) === step.actionFingerprint, "step payload fingerprint changed");

    const action = step.action || {type:step.actionType,payload:{}};
    switch(step.actionType){
      case ACTION.MOVE:{
        const x=Number(action.payload?.x), y=Number(action.payload?.y);
        need(finite(x)&&finite(y), "MOVE target is not finite");
        need(x>=4&&x<=SPACE.width-4&&y>=4&&y<=SPACE.height-4, "MOVE target outside world bounds");
        break;
      }
      case ACTION.GATHER:{
        const p=action.payload||{}, r=(observation.visibleResources||[]).find(item=>item.id===p.resourceId);
        need(!!r, "target resource is no longer observable");
        if(r){
          need(r.type===p.resourceType, "target resource type changed");
          need(r.distance<=CONFIG.interactRange+2, "target resource outside interaction range");
        }
        need(({water:"water",berry:"food",tree:"wood",herb:"medicine"}[p.resourceType]||null)===p.carryType, "resource/carry mapping invalid");
        break;
      }
      case ACTION.BUILD:
        need(agent.role==="human" && humanCanAttempt(agent,"build"), "human build capability gate rejected");
        need(observation.camp?.visible===true, "camp is not observable for construction");
        need(Number(observation.camp?.distance)<=45, "outside construction zone");
        break;
      case ACTION.HEAL:
        need(agent.role==="human" && humanCanAttempt(agent,"heal"), "human heal capability gate rejected");
        need((observation.nearbyAgents||[]).some(item=>item.id===action.payload?.targetAgentId), "patient no longer observable");
        break;
      case ACTION.REST:
      case ACTION.WAIT:
        need(agent.alive===true, "actor unavailable");
        break;
      default:
        need(false, `unsupported action ${step.actionType}`);
    }
    return {ok:errors.length===0, errors:errors.slice(0,12)};
  }

  function invalidated(plan, action){
    const fingerprint=sig(action);
    return (plan.invalidatedActionFingerprints||[]).some(item=>item.fingerprint===fingerprint);
  }

  function waitFor(state, agent, queue, reason, plan, step){
    queue.enqueue(state.tick, agent.id, ACTION.WAIT, {}, reason, {
      provider:"p4.2",
      validated:true,
      p4PlanId:plan?.planId || null,
      p4StepId:step?.stepId || null,
      p4HardeningVersion:VERSION
    });
    agent.runtime.lastActionType=ACTION.WAIT;
    agent.runtime.providerStatus="p4.2-wait";
    return {queued:true, worldMutation:false, actionType:ACTION.WAIT, reason};
  }

  function fail(agent, step, state, reason, failureClass){
    const plan=planFor(agent);
    if(!plan||!step)return {status:"ABORTED", reason};
    step.lastFailureReason=reason;
    step.lastFailureClass=failureClass || actionFailureClass(step.actionType,reason);
    step.lastValidatedTick=state.tick;
    plan.lastFailureReason=reason;
    plan.lastFailureClass=step.lastFailureClass;
    plan.updatedTick=state.tick;
    plan.invalidatedActionFingerprints=Array.isArray(plan.invalidatedActionFingerprints)?plan.invalidatedActionFingerprints:[];
    if(!plan.invalidatedActionFingerprints.some(item=>item.fingerprint===step.actionFingerprint)){
      plan.invalidatedActionFingerprints.push({tick:state.tick,stepId:step.stepId,fingerprint:step.actionFingerprint,reason,failureClass:step.lastFailureClass});
    }
    if(plan.invalidatedActionFingerprints.length>32)plan.invalidatedActionFingerprints.shift();

    if(state.tick>step.timeoutTick){
      step.status="TIMEOUT"; plan.status="TIMEOUT";
    }else if(step.lastFailureClass===ACTION_FAILURE_CLASS.TARGET_UNAVAILABLE){
      step.status="INVALIDATED";
      if(plan.replanCount<plan.maxReplans){
        plan.replanCount++;
        plan.status="REPLAN_REQUESTED";
      }else{
        plan.status="ABORTED";
      }
    }else if(step.onFailure==="RETRY_BOUNDED" && step.retryCount<plan.maxRetriesPerStep){
      step.retryCount++;
      step.status="PENDING";
      plan.status="ACTIVE";
    }else if(step.onFailure==="REPLAN" && plan.replanCount<plan.maxReplans){
      step.status="INVALIDATED";
      plan.replanCount++;
      plan.status="REPLAN_REQUESTED";
    }else{
      step.status=step.lastFailureClass==="TIMEOUT"?"TIMEOUT":"ABORTED";
      plan.status=step.status;
    }
    trace(agent, `P4.2 ${step.status}: ${reason} [${step.lastFailureClass}]`);
    return {status:plan.status, stepStatus:step.status, failureClass:step.lastFailureClass};
  }

  function applyOutcome(agent, outcome){
    const plan=planFor(agent);
    const step=plan && stepFor(plan, outcome?.p4StepId);
    if(!step)return null;

    const resolvedTick=now();
    const failureClass=outcome.ok ? null : (outcome.failureClass || actionFailureClass(step.actionType,outcome.message));
    step.outcome={
      ok:!!outcome.ok,
      message:String(outcome.message || ""),
      actionType:outcome.actionType,
      resolvedTick,
      actual:copy(outcome.actual || {ok:!!outcome.ok,message:String(outcome.message || "")}),
      error:copy(outcome.error || (outcome.ok ? null : {failureClass,message:String(outcome.message || "")}))
    };
    step.predictionStatus=step.prediction ? (failureClass==="PREDICTION_STALE" ? "STALE" : "RESOLVED") : "NONE";
    if(outcome.ok){
      step.status="COMPLETED";
      step.lastFailureReason=null;
      step.lastFailureClass=null;
      const index=plan.steps.findIndex(item=>item.stepId===step.stepId);
      const next=plan.steps[index+1];
      if(next){
        plan.currentStepIndex=index+1;
        plan.currentStepId=next.stepId;
        next.status="PENDING";
        plan.status="ACTIVE";
      }else{
        plan.currentStepIndex=index;
        plan.currentStepId=null;
        plan.status="COMPLETED";
      }
      plan.updatedTick=resolvedTick;
      trace(agent, `P4.2 completed ${step.actionType}${next ? ` → next ${next.actionType}` : ""}`);
      return plan;
    }
    fail(agent,step,runtime.state,String(outcome.message||"resolver rejected step"),failureClass);
    return plan;
  }

  function createPlan(agentId, spec={}){
    const agent=agentFor(agentId);
    if(!agent)throw new Error("agent not found");
    const state=runtime.state;
    const planId=String(spec.planId || `p42-plan:${state.simulationId}:${state.tick}:${agent.id}:${Math.abs(hashSeed(String(spec.goal||agent.mind.goal||"goal"))).toString(16)}`);
    const steps=(Array.isArray(spec.steps)?spec.steps:[]).map((item,index)=>normaliseStep(state,agent,item,index,planId));
    if(!steps.length)throw new Error("P4.2 plan requires at least one step");
    const plan={
      version:"p4.0",
      hardeningVersion:VERSION,
      schemaVersion:"p4.2",
      planId,
      goal:String(spec.goal || agent.mind.goal || "orient").slice(0,120),
      status:"ACTIVE",
      steps,
      currentStepIndex:0,
      currentStepId:steps[0].stepId,
      createdTick:state.tick,
      updatedTick:state.tick,
      replanCount:0,
      maxReplans:Math.max(0,Math.min(MAX_REPLANS,Number(spec.maxReplans ?? MAX_REPLANS))),
      maxRetriesPerStep:Math.max(0,Math.min(MAX_RETRIES_PER_STEP,Number(spec.maxRetriesPerStep ?? MAX_RETRIES_PER_STEP))),
      lastFailureReason:null,
      lastFailureClass:null,
      invalidatedActionFingerprints:[]
    };
    agent.mind.executablePlan=plan;
    agent.mind.planBudget={windowStartTick:state.tick,replanCount:0,retryCount:0};
    trace(agent, `P4.2 created multi-step plan ${planId} (${steps.length} steps)`);
    return copy(plan);
  }

  function executeCurrent(agentId, queue, source={}){
    const agent=agentFor(agentId);
    const plan=planFor(agent);
    if(!agent||!plan)return {queued:false,worldMutation:false,reason:"no P4.2 plan"};
    const step=current(plan);
    if(!step)return {queued:false,worldMutation:false,reason:"plan has no current step"};
    const action=source.action || step.action;
    if(TERMINAL.has(step.status) || invalidated(plan,action)){
      return waitFor(runtime.state,agent,queue,"P4.2 blocked stale/terminal action",plan,step);
    }
    const check=validate(agent,step,runtime.observer.capture(runtime.state,agent),runtime.state);
    if(!check.ok){
      const failureClass=check.errors.some(error=>error.includes("no longer observable")) ? ACTION_FAILURE_CLASS.TARGET_UNAVAILABLE : actionFailureClass(step.actionType,check.errors[0]);
      fail(agent,step,runtime.state,check.errors[0]||"P4.2 precondition failed",failureClass);
      return waitFor(runtime.state,agent,queue,`P4.2 blocked: ${check.errors[0]||"invalid step"}`,plan,step);
    }
    step.status="EXECUTING";
    step.attemptCount++;
    step.lastValidatedTick=runtime.state.tick;
    const provider=source.provider || "p4.2";
    queue.enqueue(runtime.state.tick,agent.id,action.type,action.payload,source.reason || "P4.2 executable step",{
      provider,
      requestId:source.requestId || null,
      sourceTick:source.sourceTick ?? runtime.state.tick,
      confidence:source.confidence ?? null,
      validated:true,
      fallback:false,
      p4PlanId:plan.planId,
      p4StepId:step.stepId,
      p4HardeningVersion:VERSION
    });
    agent.runtime.lastActionType=action.type;
    agent.runtime.lastProvider=provider;
    agent.runtime.providerStatus="p4.2-plan-accepted";
    return {queued:true,worldMutation:false,actionType:action.type,planId:plan.planId,stepId:step.stepId};
  }

  const originalApplyAccepted=DecisionRouter.prototype.applyAccepted;
  DecisionRouter.prototype.applyAccepted=function(state,task,normalized,queue,isFallback=false){
    const plan=planFor(task?.agent);
    if(!plan)return originalApplyAccepted.call(this,state,task,normalized,queue,isFallback);
    const step=current(plan);
    const incoming=normalized?.action || {type:ACTION.WAIT,payload:{}};
    if(!step || TERMINAL.has(step.status) || invalidated(plan,incoming) || sig(incoming)!==step.actionFingerprint){
      waitFor(state,task.agent,queue,"P4.2 rejected stale provider action",plan,step);
      return;
    }
    executeCurrent(task.agent.id,queue,{action:incoming,provider:normalized.provider,requestId:normalized.requestId,sourceTick:normalized.sourceTick,confidence:normalized.confidence,reason:normalized.reason});
  };

  const originalLearn=MemorySystem.prototype.learn;
  MemorySystem.prototype.learn=function(agent,outcome){
    const result=originalLearn.call(this,agent,outcome);
    applyOutcome(agent,outcome);
    return result;
  };

  if(window.AstraLifeP42===undefined){
    window.AstraLifeP42=Object.freeze({
      version:VERSION,
      limits:Object.freeze({maxReplans:MAX_REPLANS,maxRetriesPerStep:MAX_RETRIES_PER_STEP}),
      createPlan,
      executeCurrent,
      applyOutcome:(agentId,outcome)=>{const agent=agentFor(agentId);return agent?copy(applyOutcome(agent,outcome)):null;},
      currentPlan:agentId=>{const agent=agentFor(agentId);const plan=agent&&planFor(agent);return plan?copy(plan):null;},
      currentStep:agentId=>{const agent=agentFor(agentId);const plan=agent&&planFor(agent);const step=plan&&current(plan);return step?copy(step):null;},
      canAttempt:(agentId,capability)=>{const agent=agentFor(agentId);return !!agent && agent.role==="human" && humanCanAttempt(agent,capability)===true;},
      isStaleAction:(agentId,action)=>{const agent=agentFor(agentId);const plan=agent&&planFor(agent);return !!plan && invalidated(plan,action);}
    });
  }
})();

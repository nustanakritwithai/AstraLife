import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const pageErrors = [];
  const page = await browser.newPage();
  page.on('pageerror', error => pageErrors.push(String(error?.stack || error)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);

  // runtime is a lexical binding in js/10-world-runtime.js, not window.runtime.
  await page.waitForFunction(() => window.AstraLifeP42);
  const startup = await page.evaluate(() => ({
    runtimeBinding: typeof runtime !== 'undefined' && !!runtime?.state,
    p42: !!window.AstraLifeP42,
    p42Version: window.AstraLifeP42?.version
  }));
  if (!startup.runtimeBinding || !startup.p42 || startup.p42Version !== 'p4.2') {
    throw new Error(`P4.2 startup contract failed: ${JSON.stringify(startup)}`);
  }

  const result = await page.evaluate(() => {
    const failures = [];
    const check = (name, condition, detail = {}) => { if (!condition) failures.push({ name, detail }); };
    const vector = (agent, resource = null) => ({
      tick: runtime.state.tick,
      stock: { ...runtime.state.stock },
      agent: { x: agent.body.x, y: agent.body.y, energy: agent.body.energy, hp: agent.body.hp, inventory: { ...agent.inventory } },
      resource: resource && { id: resource.id, amount: resource.amount }
    });
    const park = (agent, x = runtime.state.camp.x, y = runtime.state.camp.y) => {
      agent.role = 'human'; agent.emergentRole = 'generalist'; agent.alive = true;
      agent.body.x = x; agent.body.y = y; agent.body.energy = 95; agent.body.hp = 100;
      agent.inventory = { type: null, amount: 0 }; agent.mind.executablePlan = null; agent.mind.planBudget = null;
    };
    const fresh = seed => { runtime.state.running = false; runtime.reset(seed); runtime.state.running = false; return runtime.state.agents[0]; };
    const execute = (agent, source = {}) => {
      const queue = new ActionQueue();
      const execution = window.AstraLifeP42.executeCurrent(agent.id, queue, source);
      return { execution, queued: queue.drain() };
    };
    const resolveQueued = (queued, agent) => {
      const before = vector(agent);
      const outcomes = runtime.resolver.resolve(runtime.state, queued);
      for (const outcome of outcomes) runtime.memory.learn(agent, outcome);
      return { before, outcomes, after: vector(agent) };
    };

    // PLAN-03/04: a real resolver outcome completes step one and activates step two.
    let agent = fresh('P4.2-real-resolver-20260908'); park(agent);
    const twoStep = window.AstraLifeP42.createPlan(agent.id, { planId: 'p42-two-step', goal: 'advance two steps', steps: [
      { action: { type: ACTION.WAIT, payload: {} }, prediction: { expectedDurationTicks: 1, confidence: .8 }, assumptions: ['agent is alive'] },
      { action: { type: ACTION.WAIT, payload: {} }, prediction: { expectedDurationTicks: 1, confidence: .7 }, assumptions: ['runtime remains available'] }
    ] });
    const first = execute(agent), duplicate = execute(agent), firstResolved = resolveQueued(first.queued, agent), afterFirst = window.AstraLifeP42.currentPlan(agent.id);
    check('duplicateExecuteIsSingleFlight', first.queued.length === 1 && duplicate.queued.length === 0 && duplicate.execution?.reason === 'P4.2 step already executing', { first, duplicate });
    check('realResolverAdvancesTwoStepPlan', firstResolved.outcomes.length === 1 && firstResolved.outcomes[0].ok && afterFirst.status === 'ACTIVE' && afterFirst.currentStepIndex === 1 && afterFirst.steps[0].status === 'COMPLETED' && afterFirst.steps[1].status === 'PENDING', { twoStep, firstResolved, afterFirst });
    const second = execute(agent), secondResolved = resolveQueued(second.queued, agent), completed = window.AstraLifeP42.currentPlan(agent.id);
    check('secondStepResolvesToTerminalCompletion', secondResolved.outcomes.length === 1 && secondResolved.outcomes[0].ok && completed.status === 'COMPLETED' && completed.steps.every(step => step.status === 'COMPLETED'), { secondResolved, completed });

    // A successful fallback WAIT is not permission to complete the failed original action.
    agent = fresh('P4.2-fallback-wait-20260908'); park(agent);
    const target = runtime.state.resources.find(resource => resource.type === 'berry' && resource.amount > 2);
    agent.body.x = target.x; agent.body.y = target.y;
    const stalePlan = window.AstraLifeP42.createPlan(agent.id, { goal: 'gather target', steps: [{ action: { type: ACTION.GATHER, payload: { resourceId: target.id, resourceType: 'berry', carryType: 'food' } }, onFailure: 'REPLAN' }] });
    const beforeStale = vector(agent, target); target.amount = 0;
    const blocked = execute(agent), blockedResolution = resolveQueued(blocked.queued, agent), afterStale = window.AstraLifeP42.currentPlan(agent.id);
    check('failedFallbackWaitCannotCompleteOriginalAction', blocked.queued.length === 1 && blocked.queued[0].type === ACTION.WAIT && blockedResolution.outcomes[0]?.ok && blockedResolution.outcomes[0]?.p4StepId === null && afterStale.steps[0].status !== 'COMPLETED' && afterStale.status !== 'COMPLETED' && afterStale.steps[0].outcome === null, { stalePlan, beforeStale, blocked, blockedResolution, afterStale, afterStaleWorld: vector(agent, target) });

    // Provider overrides cannot replace the owned P4.2 action.
    agent = fresh('P4.2-source-override-20260908'); park(agent);
    window.AstraLifeP42.createPlan(agent.id, { goal: 'reject override', steps: [{ action: { type: ACTION.WAIT, payload: {} } }] });
    const override = execute(agent, { action: { type: ACTION.BUILD, payload: {} }, provider: 'test' }), overridePlan = window.AstraLifeP42.currentPlan(agent.id);
    check('sourceOverrideRejected', override.queued.length === 1 && override.queued[0].type === ACTION.WAIT && overridePlan.steps[0].status === 'PENDING', { override, overridePlan });

    // PLAN-06: bounded retry must enqueue real attempts and then reach a terminal state.
    agent = fresh('P4.2-bounded-retry-20260908'); park(agent);
    window.AstraLifeP42.createPlan(agent.id, { goal: 'bounded retry', maxRetriesPerStep: 2, steps: [{ action: { type: ACTION.BUILD, payload: {} }, onFailure: 'RETRY_BOUNDED', timeoutTicks: 30 }] });
    const retryRuns = [];
    for (let attempt = 0; attempt < 4; attempt++) {
      const run = execute(agent); retryRuns.push({ execution: run.execution, queuedTypes: run.queued.map(action => action.type), plan: window.AstraLifeP42.currentPlan(agent.id) });
      const plan = window.AstraLifeP42.currentPlan(agent.id);
      if (plan.status !== 'ACTIVE') break;
      const outcomes = runtime.resolver.resolve(runtime.state, run.queued);
      for (const outcome of outcomes) runtime.memory.learn(agent, outcome);
    }
    const retryTerminal = window.AstraLifeP42.currentPlan(agent.id);
    check('boundedRetryExecutesAndTerminates', retryRuns.filter(run => run.queuedTypes.includes(ACTION.BUILD)).length === 3 && retryTerminal.status === 'ABORTED' && retryTerminal.steps[0].retryCount === 2 && retryTerminal.steps[0].attemptCount === 3 && retryRuns.length === 4 && retryRuns[3].queuedTypes.length === 0, { retryRuns, retryTerminal });

    // PLAN-05: stale target rejection is proved by world-state equality, not the API flag.
    agent = fresh('P4.2-stale-target-20260908'); park(agent);
    const staleTarget = runtime.state.resources.find(resource => resource.type === 'berry' && resource.amount > 2);
    agent.body.x = staleTarget.x; agent.body.y = staleTarget.y;
    window.AstraLifeP42.createPlan(agent.id, { goal: 'stale target', steps: [{ action: { type: ACTION.GATHER, payload: { resourceId: staleTarget.id, resourceType: 'berry', carryType: 'food' } } }] });
    staleTarget.amount = 0; const beforeBlocked = vector(agent, staleTarget), staleExecution = execute(agent), afterBlocked = vector(agent, staleTarget);
    check('staleTargetBlockedWithoutWorldMutation', staleExecution.queued[0]?.type === ACTION.WAIT && JSON.stringify(beforeBlocked) === JSON.stringify(afterBlocked) && window.AstraLifeP42.isStaleAction(agent.id, { type: ACTION.GATHER, payload: { resourceId: staleTarget.id, resourceType: 'berry', carryType: 'food' } }), { beforeBlocked, staleExecution, afterBlocked });

    // PLAN-06 terminal timeout/stuck handling.
    agent = fresh('P4.2-timeout-terminal-20260908'); park(agent);
    window.AstraLifeP42.createPlan(agent.id, { goal: 'timeout', steps: [{ action: { type: ACTION.WAIT, payload: {} }, timeoutTicks: 1 }] });
    runtime.state.tick += 2; const timeoutRun = execute(agent), timeoutPlan = window.AstraLifeP42.currentPlan(agent.id);
    check('timeoutBecomesTerminal', timeoutRun.queued[0]?.type === ACTION.WAIT && timeoutPlan.status === 'TIMEOUT' && timeoutPlan.steps[0].status === 'TIMEOUT' && timeoutPlan.steps[0].currentExecution === null, { timeoutRun, timeoutPlan });

    // Once complete, the router releases the P4.2 ownership and a valid legacy action
    // must create a fresh P4.0 plan whose resolver outcome is actually learned.
    agent = fresh('P4.2-router-release-20260908'); park(agent);
    window.AstraLifeP42.createPlan(agent.id, { goal: 'release router', steps: [{ action: { type: ACTION.WAIT, payload: {} } }] });
    const releaseQueue = new ActionQueue();
    const releaseExec = window.AstraLifeP42.executeCurrent(agent.id, releaseQueue);
    const releaseOutcome = runtime.resolver.resolve(runtime.state, releaseQueue.drain())[0];
    runtime.memory.learn(agent, releaseOutcome);
    const legacyQueue = new ActionQueue();
    const legacyAction = { type: ACTION.WAIT, payload: {} };
    const legacyResponse = { action: legacyAction, cognition: { goal: 'legacy after p42' }, provider: 'local', requestId: 'legacy-release', sourceTick: runtime.state.tick, confidence: .8, reason: 'legacy release' };
    runtime.decisionRouter.applyAccepted(runtime.state, { agent, observation: runtime.observer.capture(runtime.state, agent), request: {}, providerId: 'local', rawResponse: legacyResponse }, legacyResponse, legacyQueue, false);
    const legacyQueued = legacyQueue.drain();
    const legacyOutcome = runtime.resolver.resolve(runtime.state, legacyQueued)[0];
    runtime.memory.learn(agent, legacyOutcome);
    const legacyPlan = agent.mind.executablePlan;
    check('terminalPlanReleasesRouter', releaseExec.queued === true && releaseOutcome?.ok === true && legacyQueued.length === 1 && legacyQueued[0].type === ACTION.WAIT && legacyOutcome?.ok === true && legacyPlan?.version === 'p4.0' && legacyPlan?.hardeningVersion === undefined && legacyPlan?.status === 'COMPLETED', { releaseExec, releaseOutcome, legacyQueued, legacyOutcome, legacyPlan });

    // PLAN-02 capability parity: hardening API agrees for human vs non-human actors.
    agent = fresh('P4.2-capability-parity-20260908'); park(agent);
    const capable = { build: window.AstraLifeP42.canAttempt(agent.id, 'build'), heal: window.AstraLifeP42.canAttempt(agent.id, 'heal') };
    agent.role = 'scout'; const incapable = { build: window.AstraLifeP42.canAttempt(agent.id, 'build'), heal: window.AstraLifeP42.canAttempt(agent.id, 'heal') };
    check('capabilityParity', capable.build === true && capable.heal === true && incapable.build === false && incapable.heal === false, { capable, incapable });

    // PLAN-07: verify the concrete persistent boundary and restore through the actual P2 API.
    agent.role = 'human'; window.AstraLifeP42.createPlan(agent.id, { goal: 'persist plan', steps: [{ action: { type: ACTION.WAIT, payload: {} }, prediction: { expectedDurationTicks: 2 }, assumptions: ['alive'] }] });
    const saved = AgentStateBoundaryV051.persistent(agent), savedPlan = JSON.parse(JSON.stringify(saved.executablePlan));
    const shapeOk = saved.agentId === agent.id && saved.executablePlanSchemaVersion === 'p4.0' && saved.executablePlan?.hardeningVersion === 'p4.2' && saved.executablePlan?.schemaVersion === 'p4.2' && saved.planBudget && savedPlan.steps.length === 1;
    agent.mind.executablePlan = null; agent.mind.planBudget = null;
    const restoreResult = AstraLifeP2.restorePersistent(agent.id, saved), restored = window.AstraLifeP42.currentPlan(agent.id);
    check('persistentExportAndActualRestore', shapeOk && restoreResult.ok === true && restored?.planId === savedPlan.planId && restored?.hardeningVersion === 'p4.2' && restored?.steps?.[0]?.prediction?.expectedDurationTicks === 2, { shapeOk, restoreResult, savedPlan, restored });

    // Applying the same resolver outcome twice must not produce a second transition.
    agent = fresh('P4.2-exactly-once-20260908'); park(agent);
    window.AstraLifeP42.createPlan(agent.id, { goal: 'exactly once', steps: [{ action: { type: ACTION.WAIT, payload: {} } }, { action: { type: ACTION.WAIT, payload: {} } }] });
    const onceRun = execute(agent), onceOutcome = runtime.resolver.resolve(runtime.state, onceRun.queued)[0];
    runtime.memory.learn(agent, onceOutcome); const onceAfterFirst = window.AstraLifeP42.currentPlan(agent.id);
    runtime.memory.learn(agent, onceOutcome); const onceAfterDuplicate = window.AstraLifeP42.currentPlan(agent.id);
    check('resolverOutcomeExactlyOnce', onceAfterFirst.currentStepIndex === 1 && onceAfterDuplicate.currentStepIndex === 1 && onceAfterDuplicate.steps[0].status === 'COMPLETED' && onceAfterDuplicate.steps[1].status === 'PENDING', { onceOutcome, onceAfterFirst, onceAfterDuplicate });

    return { ok: failures.length === 0, failures, p42: window.AstraLifeP42.version };
  });
  console.log(JSON.stringify({ startup, pageErrors, ...result }, null, 2));
  if (pageErrors.length || !result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}

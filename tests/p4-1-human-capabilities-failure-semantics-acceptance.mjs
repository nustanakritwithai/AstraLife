import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(() => window.AstraLifeP4 && window.AstraLifeP1 && window.AstraLifeV051);

  const result = await page.evaluate(() => {
    runtime.state.running = false;
    runtime.reset('P4.1-FAILURE-SEMANTICS-20260908');
    runtime.state.running = false;
    const state = runtime.state;
    const [A, B, C, D] = state.agents.slice(0, 4);
    const park = (agent, x = state.camp.x, y = state.camp.y) => {
      agent.role = 'human';
      agent.alive = true;
      agent.body.x = x;
      agent.body.y = y;
      agent.body.energy = 95;
      agent.body.hp = 100;
      agent.inventory = { type: null, amount: 0 };
    };
    [A, B, C, D].forEach(agent => park(agent));
    let sequence = 0;
    const action = (agent, type, payload = {}, meta = { validated: true }) => ({
      id: `p41-failure-${++sequence}`,
      agentId: agent.id,
      type,
      payload,
      meta
    });
    const resolveOne = queuedAction => runtime.resolver.resolve(state, [queuedAction])[0];

    const successfulWait = resolveOne(action(A, ACTION.WAIT));
    const unvalidated = resolveOne({
      id: `p41-failure-${++sequence}`,
      agentId: A.id,
      type: ACTION.WAIT,
      payload: {}
    });

    // Capability failure must not be reported as a dead/missing actor.
    C.role = 'scout';
    const buildCapabilityFailure = resolveOne(action(C, ACTION.BUILD));
    const healCapabilityFailure = resolveOne(action(C, ACTION.HEAL, { targetAgentId: D.id }));
    C.role = 'human';

    D.alive = false;
    const deadActorFailure = resolveOne(action(D, ACTION.WAIT));
    D.alive = true;

    // Being too far away is an actor constraint; it must not erase a still-valid target belief.
    const distantResource = state.resources.find(resource => resource.type === 'berry' && resource.amount > 2);
    A.body.x = state.camp.x;
    A.body.y = state.camp.y;
    const resourceKey = `resource:${distantResource.id}`;
    runtime.memory.setFact(A, resourceKey, {
      id: distantResource.id,
      type: distantResource.type,
      x: distantResource.x,
      y: distantResource.y,
      amountBand: 'high'
    }, .95, 'direct');
    const rangeFailure = resolveOne(action(A, ACTION.GATHER, {
      resourceId: distantResource.id,
      resourceType: 'berry',
      carryType: 'food'
    }));
    runtime.memory.learn(A, rangeFailure);
    const rangeBeliefPresent = A.mind.facts.has(resourceKey);

    // A genuinely unavailable target may invalidate the target belief.
    runtime.memory.setFact(A, resourceKey, {
      id: distantResource.id,
      type: distantResource.type,
      x: distantResource.x,
      y: distantResource.y,
      amountBand: 'high'
    }, .95, 'direct');
    distantResource.amount = 0;
    const targetFailure = resolveOne(action(A, ACTION.GATHER, {
      resourceId: distantResource.id,
      resourceType: 'berry',
      carryType: 'food'
    }));
    runtime.memory.learn(A, targetFailure);

    // The plan trace and persisted plan state must retain the semantic class.
    runtime.reset('P4.1-PLAN-FAILURE-20260908');
    runtime.state.running = false;
    const planAgent = runtime.state.agents[0];
    planAgent.role = 'human';
    planAgent.alive = true;
    planAgent.body.x = runtime.state.camp.x;
    planAgent.body.y = runtime.state.camp.y;
    planAgent.mind.executablePlan = null;
    planAgent.mind.planBudget = null;
    const planResource = runtime.state.resources.find(resource => resource.type === 'berry' && resource.amount > 2);
    planAgent.body.x = planResource.x;
    planAgent.body.y = planResource.y;
    const observation1 = runtime.observer.capture(runtime.state, planAgent);
    const request = runtime.requestFactory.build(runtime.state, planAgent, observation1, 'local');
    const response = makeDecisionResponse(request, 'local', {
      type: ACTION.GATHER,
      payload: { resourceId: planResource.id, resourceType: 'berry', carryType: 'food' }
    }, { goal: 'gather_food', reason: 'P4.1 failure semantics', plan: 'bounded gather' }, .8, 12, { test: 'P4.1-failure-semantics' });
    const checked = runtime.validator.validate(response, request, runtime.state);
    const queue1 = new ActionQueue();
    runtime.decisionRouter.applyAccepted(runtime.state, {
      agent: planAgent,
      observation: observation1,
      request,
      providerId: 'local',
      rawResponse: response
    }, checked.normalized, queue1, false);
    planResource.amount = 0;
    runtime.state.resourceById.set(planResource.id, planResource);
    runtime.state.tick++;
    const observation2 = runtime.observer.capture(runtime.state, planAgent);
    const queue2 = new ActionQueue();
    runtime.decisionRouter.applyAccepted(runtime.state, {
      agent: planAgent,
      observation: observation2,
      request,
      providerId: 'local',
      rawResponse: response
    }, checked.normalized, queue2, false);
    const plan = AstraLifeP4.ensure(planAgent.id);
    const step = AstraLifeP4.currentStep(planAgent.id);
    const invalidation = plan.invalidatedActionFingerprints.at(-1);

    const tests = {
      successfulOutcomeHasNoFailureClass: successfulWait.ok && successfulWait.failureClass === null,
      unvalidatedOutcomeIsClassified: !unvalidated.ok && unvalidated.failureClass === ACTION_FAILURE_CLASS.UNVALIDATED,
      capabilityBuildIsNotActorUnavailable: buildCapabilityFailure.failureClass === ACTION_FAILURE_CLASS.CAPABILITY_UNAVAILABLE,
      capabilityHealIsNotGenericPrecondition: healCapabilityFailure.failureClass === ACTION_FAILURE_CLASS.CAPABILITY_UNAVAILABLE,
      deadActorIsActorUnavailable: deadActorFailure.failureClass === ACTION_FAILURE_CLASS.ACTOR_UNAVAILABLE,
      outOfRangeDoesNotEraseTargetBelief: rangeFailure.failureClass === ACTION_FAILURE_CLASS.OUT_OF_RANGE && rangeBeliefPresent,
      targetUnavailableErasesTargetBelief: targetFailure.failureClass === ACTION_FAILURE_CLASS.TARGET_UNAVAILABLE && !A.mind.facts.has(resourceKey),
      planStoresFailureClass: checked.ok && plan.lastFailureClass === ACTION_FAILURE_CLASS.TARGET_UNAVAILABLE && step.lastFailureClass === ACTION_FAILURE_CLASS.TARGET_UNAVAILABLE && invalidation?.failureClass === ACTION_FAILURE_CLASS.TARGET_UNAVAILABLE
    };
    return {
      ok: Object.values(tests).every(Boolean),
      tests,
      observations: {
        successfulFailureClass: successfulWait.failureClass,
        unvalidatedFailureClass: unvalidated.failureClass,
        buildCapabilityFailure,
        healCapabilityFailure,
        deadActorFailure,
        rangeFailure,
        targetFailure,
        planStatus: plan.status,
        stepStatus: step?.status,
        invalidation
      }
    };
  });

  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}

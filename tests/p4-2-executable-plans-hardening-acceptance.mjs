import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({headless:true});
try {
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(() => window.runtime && window.AstraLifeP4);
  const result = await page.evaluate(() => {
    runtime.state.running = false;
    runtime.reset('P4.2-HARDENING-20260908');
    runtime.state.running = false;
    const [agent] = runtime.state.agents;
    agent.role = 'human';
    agent.alive = true;
    agent.body.x = runtime.state.camp.x;
    agent.body.y = runtime.state.camp.y;
    agent.body.energy = 95;
    agent.mind.executablePlan = null;
    agent.mind.planBudget = null;

    const action = {type: ACTION.WAIT, payload:{}};
    const plan = window.AstraLifeP42?.createPlan(agent.id, {
      goal: 'multi-step hardening',
      steps: [
        {action, prediction:{expectedDurationTicks:2, confidence:.8}, assumptions:['agent is alive'], onFailure:'RETRY_BOUNDED'},
        {action:{type:ACTION.WAIT, payload:{}}, prediction:{expectedDurationTicks:1, confidence:.7}, assumptions:['runtime remains available'], onFailure:'ABORT'}
      ],
      maxReplans:3,
      maxRetriesPerStep:2
    });

    const q = new ActionQueue();
    const execution = window.AstraLifeP42?.executeCurrent(agent.id, q);
    const queued = q.drain();
    const persisted = window.AgentStateBoundaryV051?.persistent(agent);
    const tests = {
      apiExists: !!window.AstraLifeP42,
      multiStepPlan: !!plan && plan.steps?.length === 2,
      evidenceStored: !!plan?.steps?.[0]?.prediction && plan.steps?.[0]?.assumptions?.length === 1,
      resolverMetadata: queued.length === 1 && queued[0].meta?.p4PlanId && queued[0].meta?.p4StepId,
      noDirectMutation: execution?.worldMutation === false,
      boundedLimits: plan?.maxReplans === 3 && plan?.maxRetriesPerStep === 2,
      persistenceMetadata: persisted?.executablePlan?.hardeningVersion === 'p4.2'
    };
    return {ok:Object.values(tests).every(Boolean), tests, plan, queued, persisted};
  });
  console.log(JSON.stringify(result,null,2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}

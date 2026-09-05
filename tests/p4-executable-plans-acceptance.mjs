import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
const page=await browser.newPage();
await page.goto(pathToFileURL(path.resolve('index.html')).href);
await page.waitForFunction(()=>window.AstraLifeP4&&window.AstraLifeP3&&window.AstraLifeP2);

const result=await page.evaluate(()=>{
  runtime.state.running=false;
  const state=runtime.state;
  state.tick=12;
  const agent=state.agents[0];
  agent.role='gatherer';
  agent.alive=true;
  agent.inventory={type:null,amount:0};
  agent.mind.goal='gather_food';
  agent.mind.goalReason='PLAN-01 known berry target';
  agent.mind.plan='P4 executable plan test';
  agent.mind.executablePlan=null;
  agent.mind.planBudget=null;

  const resource=state.resources.find(r=>r.type==='berry'&&r.amount>2)||state.resources.find(r=>r.type==='water'&&r.amount>2);
  const carryType=resource.type==='berry'?'food':resource.type;
  agent.body.x=resource.x;
  agent.body.y=resource.y;
  agent.body.energy=90;
  runtime.memory.setFact(agent,`resource:${resource.id}`,{id:resource.id,type:resource.type,x:resource.x,y:resource.y,amountBand:'high'},.99,'direct');

  const obs1=runtime.observer.capture(state,agent);
  runtime.memory.ingest(agent,obs1,state);
  const request=runtime.requestFactory.build(state,agent,obs1,'local');
  const action={type:ACTION.GATHER,payload:{resourceId:resource.id,resourceType:resource.type,carryType},reason:'PLAN-01 harvest known target'};
  const response=makeDecisionResponse(request,'local',action,{goal:'gather_food',reason:'PLAN-01',plan:'bounded executable gather step'},.86,18,{test:'PLAN-01'});
  const checked=runtime.validator.validate(response,request,state);
  const queue1=new ActionQueue();
  runtime.decisionRouter.applyAccepted(state,{agent,observation:obs1,summary:{alive:state.agents.filter(a=>a.alive).length},request,providerId:'local',rawResponse:response},checked.normalized,queue1,false);
  const firstQueued=queue1.drain();
  const plan1=AstraLifeP4.ensure(agent.id), step1=AstraLifeP4.currentStep(agent.id);

  // The target disappears after planning but before the next execution/retry.
  resource.amount=0;
  state.resourceById.set(resource.id,resource);
  state.tick++;
  const obs2=runtime.observer.capture(state,agent);
  runtime.memory.ingest(agent,obs2,state);
  const queue2=new ActionQueue();
  runtime.decisionRouter.applyAccepted(state,{agent,observation:obs2,summary:{alive:state.agents.filter(a=>a.alive).length},request,providerId:'local',rawResponse:response},checked.normalized,queue2,false);
  const secondQueued=queue2.drain();
  const plan2=AstraLifeP4.ensure(agent.id), step2=AstraLifeP4.currentStep(agent.id);

  // Replaying the same stale provider output must not revive the invalidated target/action.
  const replayed=[];
  for(let i=0;i<5;i++){
    state.tick++;
    const obs=runtime.observer.capture(state,agent);
    const q=new ActionQueue();
    runtime.decisionRouter.applyAccepted(state,{agent,observation:obs,summary:{alive:state.agents.filter(a=>a.alive).length},request,providerId:'local',rawResponse:response},checked.normalized,q,false);
    replayed.push(...q.drain().map(a=>({type:a.type,reason:a.reason,meta:a.meta})));
  }
  const plan3=AstraLifeP4.ensure(agent.id), step3=AstraLifeP4.currentStep(agent.id);

  const saved=AgentStateBoundaryV051.persistent(agent);
  agent.mind.executablePlan=null;
  agent.mind.planBudget=null;
  AstraLifeP2.restorePersistent(agent.id,saved);
  const restored=AstraLifeP4.ensure(agent.id);
  runtime.selectedAgentId=agent.id;
  updateInspector();
  const inspector=ui.iwm.textContent;

  const tests={
    validatorAcceptedStructuredAction: checked.ok,
    executablePlanCreated: plan1.status==='ACTIVE'&&step1&&step1.actionType===ACTION.GATHER&&Array.isArray(step1.preconditions)&&step1.preconditions.length>=3&&step1.timeoutTick>state.tick-1,
    firstExecutionEnqueuedWithPlanMeta: firstQueued.length===1&&firstQueued[0].type===ACTION.GATHER&&!!firstQueued[0].meta.p4PlanId&&!!firstQueued[0].meta.p4StepId,
    disappearedTargetDetected: !obs2.visibleResources.some(r=>r.id===resource.id),
    currentStepInvalidated: step2.status==='INVALIDATED'||step2.status==='TIMEOUT',
    safeWaitInsteadOfStaleGather: secondQueued.length===1&&secondQueued[0].type===ACTION.WAIT&&String(secondQueued[0].reason).includes('P4 blocked'),
    resourceBeliefRemoved: !agent.mind.facts.has(`resource:${resource.id}`),
    staleProviderOutputDoesNotReviveAction: replayed.every(a=>a.type===ACTION.WAIT),
    boundedReplanningBudget: plan3.replanCount<=plan3.maxReplans&&['REPLAN_REQUESTED','ABORTED'].includes(plan3.status),
    noOutOfBudgetRetry: !step3||step3.attemptCount<=plan3.maxRetriesPerStep,
    persistedAndRestored: restored.executablePlanSchemaVersion!=='missing'&&restored.version==='p4.0'&&saved.executablePlanSchemaVersion==='p4.0'&&restored.status===saved.executablePlan.status,
    inspectorShowsExecutablePlan: inspector.includes('[P4 executable plan]')&&inspector.includes('replans=')&&inspector.includes('attempts='),
    p0IntegrityStillPasses: runtime.selfTest().ok
  };
  return {ok:Object.values(tests).every(Boolean),tests,plan1,step1,plan2,step2,plan3,step3,replayed};
});

console.log(JSON.stringify(result,null,2));
await browser.close();
if(!result.ok)process.exit(1);

import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
const page=await browser.newPage();
await page.goto(pathToFileURL(path.resolve('index.html')).href);
await page.waitForFunction(()=>window.AstraLifeP3&&window.AstraLifeP2);
const result=await page.evaluate(()=>{
  runtime.state.running=false;
  const A=runtime.state.agents[0];
  const original=AgentStateBoundaryV051.persistent(A);
  runtime.state.stormTicks=0;
  A.capacity=Math.max(4,A.capacity||4);
  A.inventory={type:'water',amount:A.capacity*.9};
  A.body.x=300;A.body.y=300;A.body.energy=90;
  A.mind.worldModel=null;
  const start=AstraLifeP3.ensure(A.id).travel.loadPenalty;
  const act1={id:'wm01-a1',agentId:A.id,type:ACTION.MOVE,payload:{x:420,y:300,speed:1},reason:'wm01 heavy load'};
  const outcome1=runtime.resolver.resolveMove(runtime.state,A,act1);
  const pending=AstraLifeP3.ensure(A.id).predictions.at(-1);
  const unchangedBeforeLearn=AstraLifeP3.ensure(A.id).travel.loadPenalty===start&&pending.status==='PENDING';
  runtime.memory.learn(A,outcome1);
  const wm1=AstraLifeP3.ensure(A.id),p1=wm1.predictions.at(-1),err1=p1.error.energyAbs,after1=wm1.travel.loadPenalty;

  A.body.x=300;A.body.y=300;A.body.energy=90;A.inventory={type:'water',amount:A.capacity*.9};
  const act2={id:'wm01-a2',agentId:A.id,type:ACTION.MOVE,payload:{x:420,y:300,speed:1},reason:'wm01 heavy load repeat'};
  const outcome2=runtime.resolver.resolveMove(runtime.state,A,act2);
  runtime.memory.learn(A,outcome2);
  const wm2=AstraLifeP3.ensure(A.id),p2=wm2.predictions.at(-1),err2=p2.error.energyAbs;

  const predictionRecorded=p1.status==='RESOLVED'&&p1.predicted.energyCost>0&&p1.actual.energyCost>0;
  const wm01=unchangedBeforeLearn&&predictionRecorded&&after1<start&&err2<err1&&p2.adjustment.after<p2.adjustment.before;
  const lesson=A.mind.memory.find(e=>String(e.lesson||'').includes('adjust travel estimate'));
  const construction=AstraLifeP3.predictConstruction(A.id,3);
  const storm=AstraLifeP3.predictStormRisk(A.id);
  const saved=AgentStateBoundaryV051.persistent(A),savedPenalty=saved.worldModel.travel.loadPenalty;
  A.mind.worldModel=null;AstraLifeP2.restorePersistent(A.id,saved);const restoredPenalty=AstraLifeP3.ensure(A.id).travel.loadPenalty;
  const persistence=saved.worldModelSchemaVersion==='p3.0'&&Math.abs(restoredPenalty-savedPenalty)<1e-12;
  runtime.selectedAgentId=A.id;updateInspector();const inspector=ui.iwm.textContent;
  const inspectorShowsPrediction=inspector.includes('[P3 prediction]')&&inspector.includes('pred energy=')&&inspector.includes('error=');
  AstraLifeP2.restorePersistent(A.id,original);
  const tests={WM01_predictionErrorAndAdjustment:wm01,calibrationOccursInLearnPhase:unchangedBeforeLearn,predictionOutcomeRecorded:predictionRecorded,learningEpisodeRecorded:!!lesson,constructionEstimateAvailable:construction?.predictedProgress>0,stormRiskEstimateAvailable:Number.isFinite(storm?.risk),worldModelPersists:persistence,inspectorShowsPredictionOutcome:inspectorShowsPrediction,P0IntegrityStillPasses:runtime.selfTest().ok};
  return {ok:Object.values(tests).every(Boolean),tests,startPenalty:start,afterFirst:after1,error1:err1,error2:err2,samples:wm2.travel.samples,mae:wm2.travel.mae};
});
console.log(JSON.stringify(result,null,2));
await browser.close();
if(!result.ok)process.exit(1);

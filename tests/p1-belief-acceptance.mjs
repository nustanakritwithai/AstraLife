import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
const page=await browser.newPage();
await page.goto(pathToFileURL(path.resolve('index.html')).href);
await page.waitForFunction(()=>window.AstraLifeP1&&window.AstraLifeKnowledgeBoundary);
const result=await page.evaluate(()=>{
  runtime.state.running=false;
  const [A,B,C]=runtime.state.agents.slice(0,3);
  const park=(a,x,y)=>{a.body.x=x;a.body.y=y;a.social.inbox.length=0;a.mind.facts.clear();a.mind.beliefs?.clear();a.mind.evidence?.clear();a.mind.newFactKeys.length=0};
  park(A,500,350);park(B,510,350);park(C,900,650);
  for(const a of [A,B,C]){a.social.trust.set(A.id,.7);a.social.trust.set(B.id,.7);a.social.trust.set(C.id,.7)}

  // Real direct observation: A sees a nearby water resource and ingests it.
  const rid=990001;
  const resource={id:rid,type:'water',x:504,y:350,amount:90,max:90};
  runtime.state.resources.push(resource);runtime.state.resourceById.set(rid,resource);
  runtime.state.tick=10;
  let obsA=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,obsA,runtime.state);
  const key=`resource:${rid}`,aDirect=AstraLifeP1.activeFor(A.id,key);
  const newFactKeyPreserved=A.mind.newFactKeys.includes(key);

  // Real SHARE -> inbox -> observation -> ingest path: A reports only to B.
  const af=A.mind.facts.get(key);
  const shareAB={id:88001,tick:runtime.state.tick,agentId:A.id,type:ACTION.SHARE,payload:{intent:'REPORT',targetAgentId:B.id,replyTo:null,urgency:.7,text:'water report',facts:[{key,value:cloneJson(af.value),confidence:af.confidence,originEvidenceId:af.originEvidenceId,claimFingerprint:af.claimFingerprint}]},reason:'p1 integration',priority:PRIORITY.SHARE,meta:{validated:true}};
  const outAB=runtime.resolver.resolve(runtime.state,[shareAB])[0];
  runtime.state.tick=11;
  const obsB=runtime.observer.capture(runtime.state,B);runtime.memory.ingest(B,obsB,runtime.state);
  const bBelief=AstraLifeP1.activeFor(B.id,key);
  const obs02_B=outAB.ok&&bBelief?.status==='UNVERIFIED'&&bBelief?.sourceAgentId===A.id&&bBelief?.originEvidenceId===aDirect.originEvidenceId;
  const obs02_C=AstraLifeP1.activeFor(C.id,key)===null&&C.social.inbox.length===0;

  // Move B next to C, relay through the real message path, then C relays back to A.
  B.body.x=890;B.body.y=650;
  const bf=B.mind.facts.get(key);
  const shareBC={id:88002,tick:runtime.state.tick,agentId:B.id,type:ACTION.SHARE,payload:{intent:'REPORT',targetAgentId:C.id,urgency:.7,text:'relay',facts:[{key,value:cloneJson(bf.value),confidence:bf.confidence,originEvidenceId:bf.originEvidenceId,claimFingerprint:bf.claimFingerprint}]},reason:'relay',priority:PRIORITY.SHARE,meta:{validated:true}};
  runtime.resolver.resolve(runtime.state,[shareBC]);runtime.state.tick=12;
  const obsC=runtime.observer.capture(runtime.state,C);runtime.memory.ingest(C,obsC,runtime.state);
  const cBelief=AstraLifeP1.activeFor(C.id,key);
  const bel01=cBelief?.originEvidenceId===aDirect.originEvidenceId&&AstraLifeP1.getBeliefs(C.id).filter(b=>b.originEvidenceId===aDirect.originEvidenceId&&b.claimFingerprint===aDirect.claimFingerprint).length===1;

  C.body.x=500;C.body.y=355;
  const cf=C.mind.facts.get(key);
  const shareCA={id:88003,tick:runtime.state.tick,agentId:C.id,type:ACTION.SHARE,payload:{intent:'REPORT',targetAgentId:A.id,urgency:.7,text:'loopback',facts:[{key,value:cloneJson(cf.value),confidence:cf.confidence,originEvidenceId:cf.originEvidenceId,claimFingerprint:cf.claimFingerprint}]},reason:'loopback',priority:PRIORITY.SHARE,meta:{validated:true}};
  runtime.resolver.resolve(runtime.state,[shareCA]);runtime.state.tick=13;
  obsA=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,obsA,runtime.state);
  const aAfterLoop=AstraLifeP1.activeFor(A.id,key);
  const loopbackDoesNotDowngradeDirect=aAfterLoop?.status==='CONFIRMED'&&aAfterLoop?.sourceKind==='direct'&&aAfterLoop?.observedTick===13;

  // Latest direct observation wins even with lower confidence/amount band.
  resource.amount=5;runtime.state.tick=14;
  obsA=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,obsA,runtime.state);
  const latestFact=A.mind.facts.get(key),latestBelief=AstraLifeP1.activeFor(A.id,key);
  const latestObservationReplacesOldHigh=latestFact?.value?.amountBand==='low'&&latestBelief?.value?.amountBand==='low'&&latestBelief?.status==='CONFIRMED';

  // STALE must disappear from Planner/provider symbolic facts.
  runtime.memory.markBeliefStale(A,key);
  const staleExcludedFromFacts=!A.mind.facts.has(key);
  const obsForRequest=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,obsForRequest,runtime.state);
  runtime.memory.markBeliefStale(A,key);
  const req=runtime.requestFactory.build(runtime.state,A,obsForRequest,'local');
  const staleExcludedFromPlanner=!req.memory.symbolicFacts.some(f=>f.key===key);

  // Later absence/change does not penalize the original reporter automatically.
  const trustBefore=B.social.trust.get(A.id);runtime.memory.markBeliefStale(B,key);const trustAfter=B.social.trust.get(A.id);
  const bel02=trustBefore===trustAfter&&!B.mind.facts.has(key);

  // Confirmed beliefs age to STALE and stores remain bounded.
  runtime.state.tick=400;
  const emptyObs=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,emptyObs,runtime.state);
  const confirmedExpires=AstraLifeP1.getBeliefs(A.id).filter(b=>b.key===key).every(b=>b.status!=='CONFIRMED');
  for(let i=0;i<260;i++)runtime.memory.setFact(A,`cap:${i}`,{n:i},.7,'direct');
  const bounded=AstraLifeP1.getBeliefs(A.id).length<=160&&AstraLifeP1.getEvidence(A.id).length<=220;

  const persistent=AgentStateBoundaryV051.persistent(A);
  const persisted=Array.isArray(persistent.beliefs)&&Array.isArray(persistent.evidence)&&persistent.beliefSchemaVersion==='p1.1';
  const tests={
    OBS02_realShareInboxObservationIngest:obs02_B&&obs02_C,
    provenanceSurvivesRealMessagePacket:bBelief?.originEvidenceId===aDirect.originEvidenceId,
    BEL01_realRumorLoopKeepsSingleOrigin:bel01,
    rumorLoopDoesNotDowngradeDirectBelief:loopbackDoesNotDowngradeDirect,
    latestDirectObservationOverridesOlderHigh:latestObservationReplacesOldHigh,
    staleExcludedFromLegacyFacts:staleExcludedFromFacts,
    staleExcludedFromPlannerRequest:staleExcludedFromPlanner,
    BEL02_staleDoesNotPenalizeReporter:bel02,
    newFactKeysPreserved:newFactKeyPreserved,
    confirmedBeliefsExpire:confirmedExpires,
    beliefEvidenceStoresBounded:bounded,
    beliefAndEvidencePersistThroughAgentBoundary:persisted,
    P0IntegrityStillPasses:runtime.selfTest().ok
  };
  return {ok:Object.values(tests).every(Boolean),tests,aDirect,bBelief,cBelief,aAfterLoop,latestFact,latestBelief,trustBefore,trustAfter,counts:{beliefs:AstraLifeP1.getBeliefs(A.id).length,evidence:AstraLifeP1.getEvidence(A.id).length}};
});
console.log(JSON.stringify(result,null,2));
await browser.close();
if(!result.ok)process.exit(1);

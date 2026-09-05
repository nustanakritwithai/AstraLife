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

  // Fixture geometry: sender/receiver are within communication range (205),
  // while the resource stays beyond even max scout observation range (165)
  // for B/C. This ensures B/C can only learn the resource through messages.
  park(A,400,350);park(B,585,350);park(C,770,350);
  for(const a of [A,B,C]){a.social.trust.set(A.id,.7);a.social.trust.set(B.id,.7);a.social.trust.set(C.id,.7)}

  const rid=990001;
  const resource={id:rid,type:'water',x:404,y:350,amount:90,max:90};
  runtime.state.resources.push(resource);runtime.state.resourceById.set(rid,resource);
  runtime.state.tick=10;

  // A observes directly. B/C are >165 units from the resource and cannot see it.
  let obsA=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,obsA,runtime.state);
  const key=`resource:${rid}`,aDirect=AstraLifeP1.activeFor(A.id,key);
  const newFactKeyPreserved=A.mind.newFactKeys.includes(key);
  const preObsB=runtime.observer.capture(runtime.state,B),preObsC=runtime.observer.capture(runtime.state,C);
  const fixtureIsolation=(preObsB.visibleResources||[]).every(r=>r.id!==rid)&&(preObsC.visibleResources||[]).every(r=>r.id!==rid);

  // Real SHARE -> inbox -> observation -> ingest path: A reports only to B.
  const af=A.mind.facts.get(key);
  const shareAB={id:88001,tick:runtime.state.tick,agentId:A.id,type:ACTION.SHARE,payload:{intent:'REPORT',targetAgentId:B.id,replyTo:null,urgency:.7,text:'water report',facts:[{key,value:cloneJson(af.value),confidence:af.confidence,originEvidenceId:af.originEvidenceId,claimFingerprint:af.claimFingerprint}]},reason:'p1 integration',priority:PRIORITY.SHARE,meta:{validated:true}};
  const outAB=runtime.resolver.resolve(runtime.state,[shareAB])[0];
  runtime.state.tick=11;
  const obsB=runtime.observer.capture(runtime.state,B);runtime.memory.ingest(B,obsB,runtime.state);
  const bBelief=AstraLifeP1.activeFor(B.id,key);
  const obs02_B=fixtureIsolation&&outAB.ok&&bBelief?.status==='UNVERIFIED'&&bBelief?.sourceAgentId===A.id&&bBelief?.sourceKind==='message'&&bBelief?.originEvidenceId===aDirect.originEvidenceId;
  const obs02_C=AstraLifeP1.activeFor(C.id,key)===null&&C.social.inbox.length===0;

  // B and C are already within communication range and C still cannot observe resource.
  const bf=B.mind.facts.get(key);
  const shareBC={id:88002,tick:runtime.state.tick,agentId:B.id,type:ACTION.SHARE,payload:{intent:'REPORT',targetAgentId:C.id,urgency:.7,text:'relay',facts:[{key,value:cloneJson(bf.value),confidence:bf.confidence,originEvidenceId:bf.originEvidenceId,claimFingerprint:bf.claimFingerprint}]},reason:'relay',priority:PRIORITY.SHARE,meta:{validated:true}};
  const outBC=runtime.resolver.resolve(runtime.state,[shareBC])[0];runtime.state.tick=12;
  const obsC=runtime.observer.capture(runtime.state,C);runtime.memory.ingest(C,obsC,runtime.state);
  const cBelief=AstraLifeP1.activeFor(C.id,key);
  const bel01=outBC.ok&&cBelief?.sourceKind==='message'&&cBelief?.originEvidenceId===aDirect.originEvidenceId&&AstraLifeP1.getBeliefs(C.id).filter(b=>b.originEvidenceId===aDirect.originEvidenceId&&b.claimFingerprint===aDirect.claimFingerprint).length===1;

  // Move C within communication range of A, but loopback must not downgrade A's direct belief.
  C.body.x=585;C.body.y=355;
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

  // Expiry test is intentionally isolated from direct observation refresh.
  // Create a separate confirmed belief, then remove its observable source before advancing time.
  const expiryKey='expiry:confirmed:test';
  runtime.state.tick=20;
  runtime.memory.setFact(A,expiryKey,{value:'known-now'},.95,'direct');
  const expiryBefore=AstraLifeP1.activeFor(A.id,expiryKey);
  runtime.state.resources=runtime.state.resources.filter(r=>r.id!==rid);runtime.state.resourceById.delete(rid);
  A.body.x=1100;A.body.y=650;
  runtime.state.tick=(expiryBefore?.expiresAtTick||20)+1;
  const expiryObs=runtime.observer.capture(runtime.state,A);runtime.memory.ingest(A,expiryObs,runtime.state);
  const expiryBeliefs=AstraLifeP1.getBeliefs(A.id).filter(b=>b.key===expiryKey);
  const confirmedExpires=expiryBeliefs.length>0&&expiryBeliefs.every(b=>b.status!=='CONFIRMED')&&!A.mind.facts.has(expiryKey);

  // Stores remain bounded.
  for(let i=0;i<260;i++)runtime.memory.setFact(A,`cap:${i}`,{n:i},.7,'direct');
  const bounded=AstraLifeP1.getBeliefs(A.id).length<=160&&AstraLifeP1.getEvidence(A.id).length<=220;

  const persistent=AgentStateBoundaryV051.persistent(A);
  const persisted=Array.isArray(persistent.beliefs)&&Array.isArray(persistent.evidence)&&persistent.beliefSchemaVersion==='p1.1';
  const tests={
    fixtureKeepsResourceInvisibleToReceivers:fixtureIsolation,
    OBS02_realShareInboxObservationIngest:obs02_B&&obs02_C,
    provenanceSurvivesRealMessagePacket:bBelief?.sourceKind==='message'&&bBelief?.originEvidenceId===aDirect.originEvidenceId,
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
  return {ok:Object.values(tests).every(Boolean),tests,aDirect,bBelief,cBelief,aAfterLoop,latestFact,latestBelief,expiryBefore,expiryBeliefs,trustBefore,trustAfter,counts:{beliefs:AstraLifeP1.getBeliefs(A.id).length,evidence:AstraLifeP1.getEvidence(A.id).length}};
});
console.log(JSON.stringify(result,null,2));
await browser.close();
if(!result.ok)process.exit(1);

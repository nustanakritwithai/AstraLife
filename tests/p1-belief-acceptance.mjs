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
  const key='resource:p1-test-water';
  const value={id:777001,type:'water',x:1100,y:680,amountBand:'high'};
  for(const a of [A,B,C]){a.mind.facts.delete(key);a.mind.beliefs?.clear();a.mind.evidence?.clear();a.social.trust.set(A.id,.7);a.social.trust.set(B.id,.7);a.social.trust.set(C.id,.7)}

  runtime.memory.setFact(A,key,value,.96,'direct');
  const aBelief=AstraLifeP1.activeFor(A.id,key);
  const msgAB={id:91001,from:A.id,to:B.id,tick:runtime.state.tick,intent:'REPORT'};
  runtime.memory.receiveBelief(B,{key,value,confidence:.9,originEvidenceId:aBelief.originEvidenceId,claimFingerprint:aBelief.claimFingerprint},msgAB);
  const bBelief=AstraLifeP1.activeFor(B.id,key);
  const obs02_B=bBelief?.status==='UNVERIFIED'&&bBelief?.sourceAgentId===A.id;
  const obs02_C=AstraLifeP1.activeFor(C.id,key)===null;

  const msgBC={id:91002,from:B.id,to:C.id,tick:runtime.state.tick,intent:'REPORT'};
  runtime.memory.receiveBelief(C,{key,value,confidence:.8,originEvidenceId:bBelief.originEvidenceId,claimFingerprint:bBelief.claimFingerprint},msgBC);
  const cBelief=AstraLifeP1.activeFor(C.id,key);
  const msgCA={id:91003,from:C.id,to:A.id,tick:runtime.state.tick,intent:'REPORT'};
  runtime.memory.receiveBelief(A,{key,value,confidence:.75,originEvidenceId:cBelief.originEvidenceId,claimFingerprint:cBelief.claimFingerprint},msgCA);
  const sameOrigin=bBelief.originEvidenceId===cBelief.originEvidenceId;
  const cSameOriginCount=AstraLifeP1.getBeliefs(C.id).filter(b=>b.originEvidenceId===bBelief.originEvidenceId&&b.claimFingerprint===bBelief.claimFingerprint).length;
  const bel01=sameOrigin&&cSameOriginCount===1;

  const trustBefore=B.social.trust.get(A.id);
  runtime.memory.verifyClaim(B,A.id,runtime.state,false,key);
  const trustAfter=B.social.trust.get(A.id);
  const revised=AstraLifeP1.getBeliefs(B.id).filter(b=>b.key===key);
  const bel02=trustBefore===trustAfter&&revised.some(b=>b.status==='STALE');

  runtime.memory.confirmBelief(C,key,value,runtime.state.tick+1);
  const confirmed=AstraLifeP1.activeFor(C.id,key)?.status==='CONFIRMED';
  const persistent=AgentStateBoundaryV051.persistent(C);
  const persisted=Array.isArray(persistent.beliefs)&&Array.isArray(persistent.evidence)&&persistent.beliefSchemaVersion==='p1.0';

  const tests={
    OBS02_reportDeliveredOnlyToB:obs02_B&&obs02_C,
    BEL01_sameOriginRumorDoesNotMultiplyIndependentEvidence:bel01,
    BEL02_laterContradictionBecomesStaleWithoutTrustPenalty:bel02,
    directObservationCanConfirmBelief:confirmed,
    beliefAndEvidencePersistThroughAgentBoundary:persisted,
    P0IntegrityStillPasses:runtime.selfTest().ok
  };
  return {ok:Object.values(tests).every(Boolean),tests,aBelief,bBelief,cBelief,trustBefore,trustAfter,persistentCounts:{beliefs:persistent.beliefs.length,evidence:persistent.evidence.length}};
});
console.log(JSON.stringify(result,null,2));
await browser.close();
if(!result.ok)process.exit(1);

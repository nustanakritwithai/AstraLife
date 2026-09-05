import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
const page=await browser.newPage();
await page.goto(pathToFileURL(path.resolve('index.html')).href);
await page.waitForFunction(()=>window.AstraLifeP2&&window.AstraLifeP1&&window.AstraLifeKnowledgeBoundary);
const result=await page.evaluate(()=>{
  runtime.state.running=false;
  const A=runtime.state.agents[0];
  const original=AgentStateBoundaryV051.persistent(A);

  // Legacy migration: preserve text, mark unknown metadata, never fabricate evidence.
  A.mind.memory=[{text:'legacy note without provenance',kind:'legacy'}];
  const migrated=AstraLifeP2.migrateAgent(A.id)[0];
  const migratedAgain=AstraLifeP2.migrateAgent(A.id)[0];
  const legacyMigrationSafe=migrated.event==='legacy note without provenance'&&migrated.legacy===true&&migrated.sourceKnown===false&&migrated.observedTick===null&&migrated.evidenceIds.length===0;
  const unknownTimeStableAcrossRemigration=migratedAgain.observedTick===null&&migratedAgain.context?.timeKnown===false;

  // Unknown timestamps must also survive persistence/restore without becoming synthetic tick 0.
  const unknownSnapshot=AgentStateBoundaryV051.persistent(A);
  A.mind.memory=[];
  AstraLifeP2.restorePersistent(A.id,unknownSnapshot);
  const unknownAfterRestore=A.mind.memory[0];
  const unknownTimeStableAcrossRestore=unknownAfterRestore?.observedTick===null&&unknownAfterRestore?.context?.timeKnown===false;

  // MEM-01: force compaction and verify important lesson + evidence + applicability + exception survive.
  A.mind.memory=[];
  runtime.state.tick=50;
  runtime.memory.remember(A,'water route blocked by storm','failure',{lesson:'avoid north water route during storm',evidenceIds:['ev:storm:50'],applicability:'storm-active',exception:'route reopened after storm'});
  for(let i=0;i<90;i++){
    runtime.state.tick=51+i;
    runtime.memory.remember(A,`routine memory ${i}`,'episode',{importance:.2,context:{index:i}});
  }
  const compacted=AstraLifeP2.compact(A.id);
  const compactSummary=compacted.find(e=>e.context?.kind==='compact'&&(e.evidenceIds||[]).includes('ev:storm:50'));
  const mem01=!!compactSummary&&String(compactSummary.lesson||'').includes('avoid north water route during storm')&&compactSummary.context.applicability.includes('storm-active')&&compactSummary.context.exceptions.includes('route reopened after storm')&&compacted.length<=AstraLifeP2.maxEpisodes;

  // Retrieval must respect token cap and favor relevant retained lessons.
  const retrieval=AstraLifeP2.retrieve(A.id,'storm water route',{limit:5,tokenCap:500,tick:runtime.state.tick});
  const retrievalBounded=retrieval.estimatedTokens<=500&&retrieval.episodes.length<=5&&retrieval.episodes.some(e=>String(e.lesson||'').includes('storm'));

  // SAVE-01: save structured memory/belief/evidence/identity/session, mutate, restore, verify preservation.
  runtime.state.tick=200;
  runtime.memory.setFact(A,'save:test',{value:'persist-me'},.93,'direct');
  runtime.memory.remember(A,'save restore lesson','learning',{lesson:'restore structured memory',evidenceIds:['ev:save:200']});
  const saved=AgentStateBoundaryV051.persistent(A);
  const savedBelief=saved.beliefs.find(b=>b.key==='save:test');
  const savedMemory=saved.memory.find(e=>e.lesson==='restore structured memory');
  const beforeSession=saved.providerSession.sessionId;
  A.mind.memory=[];A.mind.beliefs?.clear();A.mind.evidence?.clear();A.mind.facts.clear();A.social.trust.clear();A.runtime.providerSessionId='mutated-session';
  const restored=AstraLifeP2.restorePersistent(A.id,saved);
  const after=AgentStateBoundaryV051.persistent(A);
  const restoredFact=A.mind.facts.get('save:test');
  const restoreObs=runtime.observer.capture(runtime.state,A);
  const restoreReq=runtime.requestFactory.build(runtime.state,A,restoreObs,'local');
  const plannerSeesRestoredBelief=restoreReq.memory.symbolicFacts.some(f=>f.key==='save:test'&&f.value?.value==='persist-me');
  const save01=restored.ok&&after.agentId===saved.agentId&&after.identity.id===saved.identity.id&&after.providerSession.sessionId===beforeSession&&after.memory.some(e=>e.episodeId===savedMemory?.episodeId&&e.evidenceIds.includes('ev:save:200'))&&after.beliefs.some(b=>b.beliefId===savedBelief?.beliefId)&&Array.isArray(after.evidence)&&restoredFact?.value?.value==='persist-me'&&plannerSeesRestoredBelief;

  // Inspector contract: memory is structured and UI renders without chain-of-thought claims.
  runtime.selectedAgentId=A.id;updateInspector();
  const inspectorText=ui.imem.textContent;
  const inspectorStructured=inspectorText.includes('restore structured memory')&&!/chain[- ]of[- ]thought/i.test(inspectorText);

  // Restore original fixture to avoid contaminating integrity check.
  AstraLifeP2.restorePersistent(A.id,original);

  const tests={legacyMigrationSafe,unknownTimeStableAcrossRemigration,unknownTimeStableAcrossRestore,MEM01_compactionRetainsLessonProvenance:mem01,retrievalBoundedAndRelevant:retrievalBounded,SAVE01_persistentRestorePreservesStructuredState:save01,plannerSeesRestoredBelief,inspectorShowsStructuredMemoryWithoutCoT:inspectorStructured,P0IntegrityStillPasses:runtime.selfTest().ok};
  return {ok:Object.values(tests).every(Boolean),tests,compactedCount:compacted.length,retrievalTokens:retrieval.estimatedTokens,savedMemorySchema:saved.memorySchemaVersion,restored};
});
console.log(JSON.stringify(result,null,2));
await browser.close();
if(!result.ok)process.exit(1);

(() => {
  "use strict";
  const BELIEF_STATUS=Object.freeze({UNVERIFIED:"UNVERIFIED",CONFIRMED:"CONFIRMED",STALE:"STALE",REFUTED:"REFUTED"});
  const P1="p1.0";
  const fp=(key,value)=>`${key}|${JSON.stringify(value)}`;
  const ensure=a=>{a.mind.beliefs=a.mind.beliefs||new Map();a.mind.evidence=a.mind.evidence||new Map();return a};
  function addEvidence(a,e){ensure(a);if(!a.mind.evidence.has(e.evidenceId))a.mind.evidence.set(e.evidenceId,Object.freeze(cloneJson(e)));return a.mind.evidence.get(e.evidenceId)}
  function upsertBelief(a,input){
    ensure(a);const fingerprint=input.claimFingerprint||fp(input.key,input.value),origin=input.originEvidenceId||input.evidenceId;
    const beliefId=input.beliefId||`belief:${a.id}:${Math.abs(hashSeed(`${fingerprint}|${origin}`)).toString(16)}`;
    const existing=a.mind.beliefs.get(beliefId),evidenceIds=[...new Set([...(existing?.evidenceIds||[]),...(input.evidenceIds||[]),input.evidenceId].filter(Boolean))];
    const next=Object.freeze({beliefId,key:input.key,claim:{subject:input.key,predicate:"value",value:cloneJson(input.value)},value:cloneJson(input.value),sourceKind:input.sourceKind||"unknown",sourceAgentId:input.sourceAgentId||null,originEvidenceId:origin,claimFingerprint:fingerprint,observedTick:input.observedTick??null,receivedTick:input.receivedTick??null,expiresAtTick:input.expiresAtTick??null,confidence:clamp(Number(input.confidence)||0,0,1),status:input.status||BELIEF_STATUS.UNVERIFIED,evidenceIds});
    a.mind.beliefs.set(beliefId,next);return next;
  }
  function activeFor(a,key){ensure(a);return [...a.mind.beliefs.values()].filter(b=>b.key===key&&b.status!==BELIEF_STATUS.REFUTED).sort((x,y)=>(y.status===BELIEF_STATUS.CONFIRMED)-(x.status===BELIEF_STATUS.CONFIRMED)||y.confidence-x.confidence)[0]||null}
  function mirror(a,key){const b=activeFor(a,key);if(!b){a.mind.facts.delete(key);return}a.mind.facts.set(key,{key,value:cloneJson(b.value),confidence:b.confidence,lastSeenTick:b.observedTick??b.receivedTick??0,source:b.sourceKind,sourceAgentId:b.sourceAgentId,originEvidenceId:b.originEvidenceId,claimFingerprint:b.claimFingerprint,beliefId:b.beliefId})}
  const oldSetFact=MemorySystem.prototype.setFact;
  MemorySystem.prototype.setFact=function(a,key,value,confidence,source="direct",sourceAgentId=null){
    ensure(a);const tick=this.tickOf(a),fingerprint=fp(key,value),direct=source==="direct"||source==="initial";
    const evidenceId=direct?`obs:${a.id}:${tick}:${fingerprint}`:`msg:${sourceAgentId||"unknown"}:${fingerprint}`;
    addEvidence(a,{evidenceId,type:direct?"observation":"message",agentId:a.id,sourceAgentId,observedTick:direct?tick:null,receivedTick:direct?null:tick,claimFingerprint:fingerprint});
    upsertBelief(a,{key,value,confidence,sourceKind:direct?"direct":"message",sourceAgentId,evidenceId,originEvidenceId:direct?evidenceId:`origin:${fingerprint}`,claimFingerprint:fingerprint,observedTick:direct?tick:null,receivedTick:direct?null:tick,expiresAtTick:tick+(direct?220:90),status:direct?BELIEF_STATUS.CONFIRMED:BELIEF_STATUS.UNVERIFIED,evidenceIds:[evidenceId]});
    mirror(a,key);if(a.mind.facts.size>CONFIG.maxFacts){const oldest=[...a.mind.facts.entries()].sort((x,y)=>x[1].lastSeenTick-y[1].lastSeenTick)[0];if(oldest)a.mind.facts.delete(oldest[0])}
  };
  MemorySystem.prototype.receiveBelief=function(a,fact,msg){
    ensure(a);const tick=this.tickOf(a),fingerprint=fact.claimFingerprint||fp(fact.key,fact.value),origin=fact.originEvidenceId||`origin:${fingerprint}`,evidenceId=`message:${msg.id}:${msg.from}:${fingerprint}`;
    addEvidence(a,{evidenceId,type:"message",agentId:a.id,sourceAgentId:msg.from,receivedTick:tick,originEvidenceId:origin,claimFingerprint:fingerprint});
    const localTrust=a.social.trust.get(msg.from)??.55,b=upsertBelief(a,{key:fact.key,value:fact.value,confidence:clamp((fact.confidence||.5)*localTrust*.92,.12,.88),sourceKind:"message",sourceAgentId:msg.from,evidenceId,originEvidenceId:origin,claimFingerprint:fingerprint,receivedTick:tick,expiresAtTick:tick+90,status:BELIEF_STATUS.UNVERIFIED,evidenceIds:[evidenceId]});mirror(a,fact.key);return b;
  };
  const oldIngest=MemorySystem.prototype.ingest;
  MemorySystem.prototype.ingest=function(a,o,state=null){oldIngest.call(this,a,o,state);ensure(a);for(const msg of o.messages||[])for(const fact of msg.facts||[])this.receiveBelief(a,fact,msg);for(const b of [...a.mind.beliefs.values()])if(b.expiresAtTick!=null&&o.tick>b.expiresAtTick&&b.status===BELIEF_STATUS.UNVERIFIED)a.mind.beliefs.set(b.beliefId,Object.freeze({...b,status:BELIEF_STATUS.STALE}));};
  MemorySystem.prototype.confirmBelief=function(a,key,value,tick=this.tickOf(a)){
    ensure(a);const fingerprint=fp(key,value);for(const b of [...a.mind.beliefs.values()])if(b.key===key){if(b.claimFingerprint===fingerprint)a.mind.beliefs.set(b.beliefId,Object.freeze({...b,status:BELIEF_STATUS.CONFIRMED,confidence:Math.max(b.confidence,.92),observedTick:tick,expiresAtTick:tick+220}));else if(b.status!==BELIEF_STATUS.STALE)a.mind.beliefs.set(b.beliefId,Object.freeze({...b,status:BELIEF_STATUS.REFUTED}))}mirror(a,key)};
  MemorySystem.prototype.markBeliefStale=function(a,key){ensure(a);for(const b of [...a.mind.beliefs.values()])if(b.key===key&&b.status!==BELIEF_STATUS.REFUTED)a.mind.beliefs.set(b.beliefId,Object.freeze({...b,status:BELIEF_STATUS.STALE}));mirror(a,key)};
  const oldShare=ActionResolver.prototype.resolveShare;
  ActionResolver.prototype.resolveShare=function(state,a,action){
    const p=cloneJson(action.payload||{});p.facts=(p.facts||[]).map(f=>{const belief=activeFor(a,f.key);return {...f,originEvidenceId:belief?.originEvidenceId||`origin:${fp(f.key,f.value)}`,claimFingerprint:belief?.claimFingerprint||fp(f.key,f.value)}});return oldShare.call(this,state,a,{...action,payload:p});
  };
  const oldPersistent=AgentStateBoundaryV051.persistent;
  AgentStateBoundaryV051.persistent=function(a){const base=cloneJson(oldPersistent.call(this,a));ensure(a);base.beliefs=[...a.mind.beliefs.values()].map(cloneJson);base.evidence=[...a.mind.evidence.values()].map(cloneJson);base.beliefSchemaVersion=P1;return deepFreeze(base)};
  const oldBundle=WorldRuntime.prototype.contractBundle;
  WorldRuntime.prototype.contractBundle=function(){return {...oldBundle.call(this),structuredBelief:{version:P1,status:Object.values(BELIEF_STATUS),rule:"Belief is not world truth. Direct observation confirms; messages create unverified beliefs with provenance; stale/refuted states are preserved."}}};
  for(const a of runtime.state.agents)ensure(a);
  window.AstraLifeP1=Object.freeze({version:P1,status:BELIEF_STATUS,getBeliefs:id=>{const a=runtime.state.agentById.get(Number(id));return a?[...ensure(a).mind.beliefs.values()].map(cloneJson):[]},getEvidence:id=>{const a=runtime.state.agentById.get(Number(id));return a?[...ensure(a).mind.evidence.values()].map(cloneJson):[]},activeFor:(id,key)=>{const a=runtime.state.agentById.get(Number(id));const b=a?activeFor(a,key):null;return b?cloneJson(b):null}});
})();

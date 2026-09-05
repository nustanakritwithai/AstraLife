(() => {
  "use strict";
  const BELIEF_STATUS=Object.freeze({UNVERIFIED:"UNVERIFIED",CONFIRMED:"CONFIRMED",STALE:"STALE",REFUTED:"REFUTED"});
  const P1="p1.1";
  const MAX_BELIEFS=160,MAX_EVIDENCE=220;
  const fp=(key,value)=>`${key}|${JSON.stringify(value)}`;
  const ensure=a=>{a.mind.beliefs=a.mind.beliefs||new Map();a.mind.evidence=a.mind.evidence||new Map();return a};
  const beliefTick=b=>Math.max(b.observedTick??-1,b.receivedTick??-1);
  function trimMap(map,max){while(map.size>max){const k=map.keys().next().value;if(k==null)break;map.delete(k)}}
  function addEvidence(a,e){ensure(a);if(!a.mind.evidence.has(e.evidenceId))a.mind.evidence.set(e.evidenceId,Object.freeze(cloneJson(e)));trimMap(a.mind.evidence,MAX_EVIDENCE);return a.mind.evidence.get(e.evidenceId)}
  function upsertBelief(a,input){
    ensure(a);const fingerprint=input.claimFingerprint||fp(input.key,input.value),origin=input.originEvidenceId||input.evidenceId;
    const beliefId=input.beliefId||`belief:${a.id}:${Math.abs(hashSeed(`${fingerprint}|${origin}`)).toString(16)}`;
    const existing=a.mind.beliefs.get(beliefId),evidenceIds=[...new Set([...(existing?.evidenceIds||[]),...(input.evidenceIds||[]),input.evidenceId].filter(Boolean))];
    const next=Object.freeze({beliefId,key:input.key,claim:{subject:input.key,predicate:"value",value:cloneJson(input.value)},value:cloneJson(input.value),sourceKind:input.sourceKind||existing?.sourceKind||"unknown",sourceAgentId:input.sourceAgentId??existing?.sourceAgentId??null,originEvidenceId:origin,claimFingerprint:fingerprint,observedTick:input.observedTick??existing?.observedTick??null,receivedTick:input.receivedTick??existing?.receivedTick??null,expiresAtTick:input.expiresAtTick??existing?.expiresAtTick??null,confidence:clamp(Number(input.confidence??existing?.confidence??0),0,1),status:input.status||existing?.status||BELIEF_STATUS.UNVERIFIED,evidenceIds});
    a.mind.beliefs.set(beliefId,next);trimMap(a.mind.beliefs,MAX_BELIEFS);return next;
  }
  function activeFor(a,key){
    ensure(a);const rank={CONFIRMED:2,UNVERIFIED:1};
    return [...a.mind.beliefs.values()].filter(b=>b.key===key&&(b.status===BELIEF_STATUS.CONFIRMED||b.status===BELIEF_STATUS.UNVERIFIED))
      .sort((x,y)=>(rank[y.status]-rank[x.status])||beliefTick(y)-beliefTick(x)||y.confidence-x.confidence)[0]||null;
  }
  function mirror(a,key){const b=activeFor(a,key);if(!b){a.mind.facts.delete(key);return}a.mind.facts.set(key,{key,value:cloneJson(b.value),confidence:b.confidence,lastSeenTick:beliefTick(b),source:b.sourceKind,sourceAgentId:b.sourceAgentId,originEvidenceId:b.originEvidenceId,claimFingerprint:b.claimFingerprint,beliefId:b.beliefId})}
  function staleOlderForKey(a,key,keepBeliefId,tick){
    for(const [id,b] of [...a.mind.beliefs])if(b.key===key&&id!==keepBeliefId&&b.status!==BELIEF_STATUS.REFUTED&&beliefTick(b)<=tick)a.mind.beliefs.set(id,Object.freeze({...b,status:BELIEF_STATUS.STALE}));
  }
  MemorySystem.prototype.setFact=function(a,key,value,confidence,source="direct",sourceAgentId=null){
    ensure(a);const tick=this.tickOf(a),fingerprint=fp(key,value),direct=source==="direct"||source==="initial";
    const evidenceId=direct?`obs:${a.id}:${tick}:${fingerprint}`:`msg:${sourceAgentId||"unknown"}:${tick}:${fingerprint}`;
    const originEvidenceId=direct?evidenceId:`origin:${fingerprint}`;
    addEvidence(a,{evidenceId,type:direct?"observation":"message",agentId:a.id,sourceAgentId,observedTick:direct?tick:null,receivedTick:direct?null:tick,originEvidenceId,claimFingerprint:fingerprint});
    const before=a.mind.facts.has(key);
    const b=upsertBelief(a,{key,value,confidence,sourceKind:direct?"direct":"message",sourceAgentId,evidenceId,originEvidenceId,claimFingerprint:fingerprint,observedTick:direct?tick:null,receivedTick:direct?null:tick,expiresAtTick:tick+(direct?220:90),status:direct?BELIEF_STATUS.CONFIRMED:BELIEF_STATUS.UNVERIFIED,evidenceIds:[evidenceId]});
    if(direct)staleOlderForKey(a,key,b.beliefId,tick);
    mirror(a,key);if(!before&&!a.mind.newFactKeys.includes(key))a.mind.newFactKeys.push(key);
    if(a.mind.facts.size>CONFIG.maxFacts){const oldest=[...a.mind.facts.entries()].sort((x,y)=>x[1].lastSeenTick-y[1].lastSeenTick)[0];if(oldest)a.mind.facts.delete(oldest[0])}
    return b;
  };
  MemorySystem.prototype.receiveBelief=function(a,fact,msg){
    ensure(a);const tick=this.tickOf(a),fingerprint=fact.claimFingerprint||fp(fact.key,fact.value),origin=fact.originEvidenceId||`origin:${fingerprint}`,evidenceId=`message:${msg.id}:${msg.from}:${fingerprint}`;
    addEvidence(a,{evidenceId,type:"message",agentId:a.id,sourceAgentId:msg.from,receivedTick:tick,originEvidenceId:origin,claimFingerprint:fingerprint});
    const existing=[...a.mind.beliefs.values()].find(b=>b.originEvidenceId===origin&&b.claimFingerprint===fingerprint);
    if(existing&&existing.status===BELIEF_STATUS.CONFIRMED&&existing.sourceKind==="direct"){
      a.mind.beliefs.set(existing.beliefId,Object.freeze({...existing,evidenceIds:[...new Set([...existing.evidenceIds,evidenceId])]}));mirror(a,fact.key);return a.mind.beliefs.get(existing.beliefId);
    }
    const localTrust=a.social.trust.get(msg.from)??.55;
    const b=upsertBelief(a,{key:fact.key,value:fact.value,confidence:clamp((fact.confidence||.5)*localTrust*.92,.12,.88),sourceKind:"message",sourceAgentId:msg.from,evidenceId,originEvidenceId:origin,claimFingerprint:fingerprint,receivedTick:tick,expiresAtTick:tick+90,status:BELIEF_STATUS.UNVERIFIED,evidenceIds:[evidenceId]});
    mirror(a,fact.key);return b;
  };
  const p01Ingest=MemorySystem.prototype.ingest;
  MemorySystem.prototype.ingest=function(a,o,state=null){
    p01Ingest.call(this,a,o,state);ensure(a);
    for(const msg of o.messages||[])for(const fact of msg.facts||[])this.receiveBelief(a,fact,msg);
    for(const [id,b] of [...a.mind.beliefs])if(b.expiresAtTick!=null&&o.tick>b.expiresAtTick&&(b.status===BELIEF_STATUS.UNVERIFIED||b.status===BELIEF_STATUS.CONFIRMED))a.mind.beliefs.set(id,Object.freeze({...b,status:BELIEF_STATUS.STALE}));
    for(const key of new Set([...a.mind.beliefs.values()].map(b=>b.key)))mirror(a,key);
  };
  const oldVerify=MemorySystem.prototype.verifyClaim;
  MemorySystem.prototype.verifyClaim=function(observer,source,state,accurate,label){
    if(accurate)return oldVerify.call(this,observer,source,state,true,label);
    ensure(observer);const fact=observer.mind.facts.get(label);if(fact?.key)this.markBeliefStale(observer,fact.key);
    this.remember(observer,`claim from Astra-${String(source||0).padStart(3,"0")} is no longer confirmed under current conditions: ${label}`,"belief-revision");
  };
  MemorySystem.prototype.confirmBelief=function(a,key,value,tick=this.tickOf(a)){
    ensure(a);const fingerprint=fp(key,value);let confirmed=null;
    for(const [id,b] of [...a.mind.beliefs])if(b.key===key){
      if(b.claimFingerprint===fingerprint){const next=Object.freeze({...b,status:BELIEF_STATUS.CONFIRMED,confidence:Math.max(b.confidence,.92),observedTick:tick,expiresAtTick:tick+220});a.mind.beliefs.set(id,next);confirmed=next}
      else if(b.status!==BELIEF_STATUS.STALE)a.mind.beliefs.set(id,Object.freeze({...b,status:BELIEF_STATUS.STALE}));
    }
    if(confirmed)staleOlderForKey(a,key,confirmed.beliefId,tick);mirror(a,key);
  };
  MemorySystem.prototype.markBeliefStale=function(a,key){ensure(a);for(const [id,b] of [...a.mind.beliefs])if(b.key===key&&b.status!==BELIEF_STATUS.REFUTED)a.mind.beliefs.set(id,Object.freeze({...b,status:BELIEF_STATUS.STALE}));mirror(a,key)};
  ActionResolver.prototype.resolveShare=function(state,agent,action){
    const p=action.payload||{},facts=(p.facts||[]).slice(0,5).filter(f=>f&&f.key);
    if(["REPORT","SYNC"].includes(p.intent)&&!facts.length)return this.outcome(action,false,"report has no factual claims");
    let recipients=[];
    if(p.targetAgentId){const target=state.agentById.get(p.targetAgentId);if(target&&target.alive&&target.id!==agent.id&&distance(agent.body,target.body)<=CONFIG.communicationRange)recipients=[target]}
    else recipients=state.agents.filter(b=>b.alive&&b.id!==agent.id&&distance(agent.body,b.body)<=CONFIG.communicationRange).sort((a,b)=>distance(agent.body,a.body)-distance(agent.body,b.body)).slice(0,8);
    if(!recipients.length)return this.outcome(action,false,"no intended peer in communication range");
    const packetFacts=facts.map(f=>{const belief=activeFor(agent,f.key);return Object.freeze({key:f.key,value:{...f.value},confidence:clamp(f.confidence,0,1),originEvidenceId:f.originEvidenceId||belief?.originEvidenceId||`origin:${fp(f.key,f.value)}`,claimFingerprint:f.claimFingerprint||belief?.claimFingerprint||fp(f.key,f.value)})});
    const messageId=state.nextMessageId++;
    for(const receiver of recipients){
      const packet=Object.freeze({protocol:PROTOCOL.communication,id:messageId,from:agent.id,to:receiver.id,intent:p.intent||"SYNC",tick:state.tick,urgency:clamp(p.urgency??.45,0,1),text:String(p.text||"").slice(0,180),replyTo:p.replyTo||null,facts:packetFacts});
      receiver.social.inbox.push(packet);if(receiver.social.inbox.length>CONFIG.maxSocialInbox)receiver.social.inbox.shift();state.effects.messages.push({fromId:agent.id,toId:receiver.id,bornTick:state.tick,intent:packet.intent});
    }
    const r=agent.social.reputation;r.messagesSent+=recipients.length;if(p.intent==="REPORT")r.reports++;if(p.intent==="REQUEST_HELP")r.helpRequests++;if(p.intent==="OFFER")r.offers++;if(p.intent==="WARN")r.warnings++;
    state.metrics.socialMessages+=recipients.length;state.metrics.intentCounts[p.intent]=(state.metrics.intentCounts[p.intent]||0)+recipients.length;state.metrics.cooperativeActions++;state.metrics.actionCounts.SHARE++;
    return this.outcome(action,true,`${p.intent} #${messageId} → ${recipients.length} peer(s)${packetFacts.length?` · ${packetFacts.length} claim(s)`:""}`,true,{messageId,recipients:recipients.map(r=>r.id)});
  };
  const oldPersistent=AgentStateBoundaryV051.persistent;
  AgentStateBoundaryV051.persistent=function(a){const base=cloneJson(oldPersistent.call(this,a));ensure(a);base.beliefs=[...a.mind.beliefs.values()].map(cloneJson);base.evidence=[...a.mind.evidence.values()].map(cloneJson);base.beliefSchemaVersion=P1;return deepFreeze(base)};
  const oldBundle=WorldRuntime.prototype.contractBundle;
  WorldRuntime.prototype.contractBundle=function(){return {...oldBundle.call(this),structuredBelief:{version:P1,status:Object.values(BELIEF_STATUS),limits:{beliefs:MAX_BELIEFS,evidence:MAX_EVIDENCE},rule:"Belief is not world truth. Direct observation confirms; messages create unverified beliefs with provenance; stale/refuted beliefs are not mirrored into planner facts."}}};
  for(const a of runtime.state.agents)ensure(a);
  window.AstraLifeP1=Object.freeze({version:P1,status:BELIEF_STATUS,getBeliefs:id=>{const a=runtime.state.agentById.get(Number(id));return a?[...ensure(a).mind.beliefs.values()].map(cloneJson):[]},getEvidence:id=>{const a=runtime.state.agentById.get(Number(id));return a?[...ensure(a).mind.evidence.values()].map(cloneJson):[]},activeFor:(id,key)=>{const a=runtime.state.agentById.get(Number(id));const b=a?activeFor(a,key):null;return b?cloneJson(b):null}});
})();

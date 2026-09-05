(() => {
  "use strict";
  if(!window.AstraLifeP2)return;
  const base=window.AstraLifeP2;
  const originalRestore=base.restorePersistent;
  const beliefTick=b=>Math.max(b?.observedTick??-1,b?.receivedTick??-1);
  function rebuildFacts(a){
    a.mind.facts=new Map();
    const groups=new Map();
    for(const b of a.mind.beliefs?.values?.()||[]){
      if(!b?.key||!(b.status==="CONFIRMED"||b.status==="UNVERIFIED"))continue;
      if(!groups.has(b.key))groups.set(b.key,[]);
      groups.get(b.key).push(b);
    }
    const rank={CONFIRMED:2,UNVERIFIED:1};
    for(const [key,list] of groups){
      const b=list.sort((x,y)=>(rank[y.status]-rank[x.status])||beliefTick(y)-beliefTick(x)||(y.confidence||0)-(x.confidence||0))[0];
      a.mind.facts.set(key,{key,value:cloneJson(b.value),confidence:b.confidence,lastSeenTick:beliefTick(b),source:b.sourceKind,sourceAgentId:b.sourceAgentId,originEvidenceId:b.originEvidenceId,claimFingerprint:b.claimFingerprint,beliefId:b.beliefId});
    }
    return a.mind.facts;
  }
  window.AstraLifeP2=Object.freeze({...base,restorePersistent:(id,snapshot)=>{
    const result=originalRestore(id,snapshot);
    if(result?.ok){
      const a=runtime.state.agentById.get(Number(id));
      if(a)rebuildFacts(a);
    }
    return result;
  },rebuildFacts:id=>{
    const a=runtime.state.agentById.get(Number(id));
    return a?[...rebuildFacts(a).values()].map(cloneJson):[];
  }});
})();

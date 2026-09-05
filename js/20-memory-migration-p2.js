(() => {
  "use strict";

  const P2_VERSION="p2.0";
  const MAX_EPISODES=64;
  const COMPACT_BATCH=12;
  const UNKNOWN="unknown";

  const ensure=a=>{
    a.mind.memorySchemaVersion=P2_VERSION;
    a.mind.memory=Array.isArray(a.mind.memory)?a.mind.memory:[];
    return a;
  };
  const idFor=(a,tick,event,index=0)=>`episode:${a.id}:${tick}:${Math.abs(hashSeed(`${event}|${index}`)).toString(16)}`;
  const importanceFor=kind=>({failure:.95,success:.9,learning:.88,"belief-revision":.86,"social-learning":.82,social:.62,compact:.72,episode:.55}[kind]??.5);
  const lessonFor=(text,kind)=>{
    if(kind==="failure")return `avoid repeating failure: ${text}`;
    if(kind==="success")return `successful pattern: ${text}`;
    if(kind==="learning"||kind==="belief-revision"||kind==="social-learning")return text;
    return null;
  };
  const finiteTick=value=>value!==null&&value!==undefined&&value!==""&&Number.isFinite(Number(value))?Number(value):null;
  function normalizeEpisode(a,input,index=0){
    const legacy=!(input&&input.episodeId);
    const observed=finiteTick(input?.observedTick);
    const fallback=finiteTick(input?.tick);
    const tick=observed!=null?observed:fallback;
    const event=String(input?.event??input?.text??"legacy memory");
    const context=cloneJson(input?.context||{});
    if(!context.kind)context.kind=input?.kind||"legacy";
    if(!context.source)context.source=legacy?UNKNOWN:UNKNOWN;
    if(context.timeKnown==null)context.timeKnown=tick!=null;
    return Object.freeze({
      episodeId:input?.episodeId||idFor(a,tick??0,event,index),
      observedTick:tick,
      event,
      action:input?.action??null,
      perceivedOutcome:input?.perceivedOutcome??null,
      evidenceIds:Array.isArray(input?.evidenceIds)?[...new Set(input.evidenceIds.filter(Boolean))]:[],
      importance:clamp(Number(input?.importance??importanceFor(input?.kind||context.kind||"episode")),0,1),
      lesson:input?.lesson??lessonFor(event,input?.kind||context.kind||"episode"),
      context,
      legacy,
      sourceKnown:legacy?false:input?.sourceKnown!==false
    });
  }
  function migrateAgent(a){
    ensure(a);
    a.mind.memory=a.mind.memory.map((m,i)=>normalizeEpisode(a,m,i));
    return a.mind.memory;
  }
  function compact(a){
    ensure(a);migrateAgent(a);
    while(a.mind.memory.length>MAX_EPISODES){
      const old=a.mind.memory.splice(0,Math.min(COMPACT_BATCH,a.mind.memory.length-MAX_EPISODES+COMPACT_BATCH-1));
      const evidenceIds=[...new Set(old.flatMap(e=>e.evidenceIds||[]))];
      const lessonCandidates=old.filter(e=>e.lesson).sort((x,y)=>(y.importance||0)-(x.importance||0)).map(e=>e.lesson);
      const lessons=[...new Set(lessonCandidates)].slice(0,8);
      const applicability=[...new Set(old.flatMap(e=>{
        const value=e.context?.applicability;
        return Array.isArray(value)?value.filter(Boolean):(value?[value]:[]);
      }))].slice(0,8);
      const exceptions=[...new Set(old.flatMap(e=>{
        const values=[];
        if(e.context?.exception)values.push(e.context.exception);
        if(Array.isArray(e.context?.exceptions))values.push(...e.context.exceptions.filter(Boolean));
        return values;
      }))].slice(0,8);
      const compactedEpisodeIds=[...new Set(old.flatMap(e=>[e.episodeId,...(Array.isArray(e.context?.compactedEpisodeIds)?e.context.compactedEpisodeIds:[])]).filter(Boolean))];
      const start=old.flatMap(e=>[e.observedTick,e.context?.range?.startTick]).filter(Number.isFinite).sort((x,y)=>x-y)[0]??null;
      const end=old.flatMap(e=>[e.observedTick,e.context?.range?.endTick]).filter(Number.isFinite).sort((x,y)=>y-x)[0]??null;
      const summary=Object.freeze({
        episodeId:idFor(a,end??0,`compact:${old.map(e=>e.episodeId).join("|")}`),
        observedTick:end,
        event:`compacted ${old.length} episodes`,
        action:null,
        perceivedOutcome:`retained ${lessons.length} lesson(s) from ${old.length} episodes`,
        evidenceIds,
        importance:Math.max(.72,...old.map(e=>e.importance||0)),
        lesson:lessons.join(" | ")||"historical episode summary",
        context:{kind:"compact",source:"runtime",timeKnown:end!=null,range:{startTick:start,endTick:end},applicability,exceptions,compactedEpisodeIds},
        legacy:false,
        sourceKnown:old.every(e=>e.sourceKnown!==false)
      });
      a.mind.memory.unshift(summary);
    }
    return a.mind.memory;
  }
  function scoreEpisode(e,query,tick){
    const terms=String(query||"").toLowerCase().split(/\s+/).filter(Boolean);
    const hay=`${e.event} ${e.lesson||""} ${JSON.stringify(e.context||{})}`.toLowerCase();
    const relevance=terms.length?terms.filter(t=>hay.includes(t)).length/terms.length:.35;
    const age=e.observedTick==null?9999:Math.max(0,(tick??e.observedTick)-e.observedTick);
    const recency=1/(1+age/120);
    const evidenceQuality=Math.min(1,(e.evidenceIds?.length||0)/3)+(e.sourceKnown?.15:0);
    return relevance*.42+recency*.22+(e.importance||0)*.26+Math.min(1,evidenceQuality)*.10;
  }
  function retrieve(a,query,{limit=8,tokenCap=900,tick=null}={}){
    migrateAgent(a);const now=tick??runtime?.state?.tick??0;let used=0,out=[];
    for(const e of [...a.mind.memory].sort((x,y)=>scoreEpisode(y,query,now)-scoreEpisode(x,query,now))){
      const cost=Math.max(8,Math.ceil(JSON.stringify(e).length/4));
      if(used+cost>tokenCap)continue;
      out.push(cloneJson(e));used+=cost;if(out.length>=limit)break;
    }
    return {episodes:out,estimatedTokens:used};
  }
  function restorePersistent(a,snapshot){
    if(!a||!snapshot||snapshot.agentId!==a.id)return {ok:false,error:"AGENT_ID_MISMATCH"};
    a.mind.memory=(snapshot.memory||[]).map((m,i)=>normalizeEpisode(a,m,i));
    compact(a);
    if(Array.isArray(snapshot.beliefs))a.mind.beliefs=new Map(snapshot.beliefs.map(b=>[b.beliefId,deepFreeze(cloneJson(b))]));
    if(Array.isArray(snapshot.evidence))a.mind.evidence=new Map(snapshot.evidence.map(e=>[e.evidenceId,deepFreeze(cloneJson(e))]));
    if(Array.isArray(snapshot.socialTrust))a.social.trust=new Map(snapshot.socialTrust.map(([id,v])=>[Number(id),Number(v)]));
    if(snapshot.skills&&a.development?.skills)for(const [k,v] of Object.entries(snapshot.skills))if(a.development.skills[k])Object.assign(a.development.skills[k],cloneJson(v));
    if(snapshot.preferences&&a.development)a.development.preferences=cloneJson(snapshot.preferences);
    if(snapshot.domainReputation&&a.development)a.development.domainReputation=cloneJson(snapshot.domainReputation);
    if(snapshot.emergentRole!=null)a.emergentRole=snapshot.emergentRole;
    if(snapshot.providerSession?.sessionId)a.runtime.providerSessionId=snapshot.providerSession.sessionId;
    if(snapshot.providerSession?.lastProvider)a.runtime.lastProvider=snapshot.providerSession.lastProvider;
    return {ok:true,memory:a.mind.memory.length,beliefs:a.mind.beliefs?.size||0,evidence:a.mind.evidence?.size||0};
  }

  MemorySystem.prototype.remember=function(a,text,kind="episode",meta={}){
    ensure(a);migrateAgent(a);const tick=this.tickOf(a);
    const episode=normalizeEpisode(a,{observedTick:tick,event:text,action:meta.action??null,perceivedOutcome:meta.perceivedOutcome??null,evidenceIds:meta.evidenceIds||[],importance:meta.importance??importanceFor(kind),lesson:meta.lesson??lessonFor(text,kind),context:{kind,source:meta.source??"runtime",timeKnown:true,applicability:meta.applicability??null,exception:meta.exception??null,...(meta.context||{})},sourceKnown:meta.sourceKnown!==false},a.mind.memory.length);
    a.mind.memory.push(episode);compact(a);return episode;
  };

  const oldPersistent=AgentStateBoundaryV051.persistent;
  AgentStateBoundaryV051.persistent=function(a){
    migrateAgent(a);compact(a);const base=cloneJson(oldPersistent.call(this,a));
    base.memory=a.mind.memory.map(cloneJson);base.memorySchemaVersion=P2_VERSION;return deepFreeze(base);
  };

  const oldUpdateInspector=window.updateInspector;
  if(typeof oldUpdateInspector==="function")window.updateInspector=function(){
    oldUpdateInspector();
    const a=runtime.selectedAgentId?runtime.state.agentById.get(runtime.selectedAgentId):null;if(!a||!ui.imem)return;
    migrateAgent(a);ui.imem.textContent=a.mind.memory.slice(-10).reverse().map(e=>`T${e.observedTick??"?"} ${e.context?.kind||"episode"}: ${e.event}${e.lesson?`\n  lesson: ${e.lesson}`:""}${e.evidenceIds?.length?`\n  evidence: ${e.evidenceIds.join(", ")}`:""}`).join("\n")||"(empty memory)";
  };

  for(const a of runtime.state.agents)migrateAgent(a);
  window.AstraLifeP2=Object.freeze({version:P2_VERSION,maxEpisodes:MAX_EPISODES,migrateAgent:id=>{const a=runtime.state.agentById.get(Number(id));return a?migrateAgent(a).map(cloneJson):[]},retrieve:(id,q,opts)=>{const a=runtime.state.agentById.get(Number(id));return a?retrieve(a,q,opts):{episodes:[],estimatedTokens:0}},compact:id=>{const a=runtime.state.agentById.get(Number(id));return a?compact(a).map(cloneJson):[]},normalizeLegacy:(id,m)=>{const a=runtime.state.agentById.get(Number(id));return a?cloneJson(normalizeEpisode(a,m,0)):null},restorePersistent:(id,snapshot)=>{const a=runtime.state.agentById.get(Number(id));return a?restorePersistent(a,snapshot):{ok:false,error:"AGENT_NOT_FOUND"}}});
})();

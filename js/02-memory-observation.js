class MemorySystem{
  tickOf(agent){return agent&&agent.runtime&&agent.runtime.lastObservation?agent.runtime.lastObservation.tick:0}
  updateCredibility(agent){
    const r=agent.social.reputation;
    const good=r.accurateClaims+1,bad=r.misleadingClaims+1;
    r.credibility=clamp(good/(good+bad),.08,.98);
  }
  verifyClaim(observer,source,state,accurate,label){
    if(!source||source===observer.id)return;
    const old=observer.social.trust.get(source)??.55;
    observer.social.trust.set(source,clamp(old+(accurate?.035:-.085),.03,.99));
    const speaker=state&&state.agentById?state.agentById.get(source):null;
    if(speaker){speaker.social.reputation.claimsVerified++; if(accurate)speaker.social.reputation.accurateClaims++; else speaker.social.reputation.misleadingClaims++; this.updateCredibility(speaker)}
    this.remember(observer,`${accurate?"verified":"disproved"} claim from Astra-${String(source).padStart(3,"0")}: ${label}`,"social-learning");
  }
  remember(agent,text,kind="episode"){
    const tick=this.tickOf(agent);
    agent.mind.memory.push({tick,kind,text});
    if(agent.mind.memory.length>CONFIG.maxMemory){
      const old=agent.mind.memory.splice(0,8);
      const kinds={};for(const m of old)kinds[m.kind]=(kinds[m.kind]||0)+1;
      const summary=Object.entries(kinds).map(([k,v])=>`${k}:${v}`).join(", ");
      agent.mind.memory.unshift({tick,kind:"compact",text:`compacted ${old.length} memories (${summary})`});
    }
  }
  trace(agent,phase,text){
    agent.runtime.trace.push({tick:this.tickOf(agent),phase,text});
    if(agent.runtime.trace.length>CONFIG.maxTrace)agent.runtime.trace.shift();
  }
  setFact(agent,key,value,confidence,source="direct",sourceAgentId=null){
    const old=agent.mind.facts.get(key);
    const incoming={key,value,confidence:clamp(confidence,0,1),lastSeenTick:this.tickOf(agent),source,sourceAgentId};
    if(!old || incoming.confidence>=old.confidence || source==="direct"){
      agent.mind.facts.set(key,incoming);
      if(!old)agent.mind.newFactKeys.push(key);
    }
    if(agent.mind.facts.size>CONFIG.maxFacts){
      const oldest=[...agent.mind.facts.entries()].sort((a,b)=>a[1].lastSeenTick-b[1].lastSeenTick)[0];
      if(oldest)agent.mind.facts.delete(oldest[0]);
    }
  }
  ingest(agent,observation,state=null){
    agent.runtime.lastObservation=observation;
    agent.mind.newFactKeys.length=0;

    if(observation.camp.stock){
      agent.mind.beliefStock={...observation.camp.stock};
      agent.mind.lastCampSyncTick=observation.tick;
      this.setFact(agent,"camp:stock",{...observation.camp.stock},.99,"direct");
    }

    for(const r of observation.visibleResources){
      const key=`resource:${r.id}`;
      const previous=agent.mind.facts.get(key);
      if(previous && previous.sourceAgentId){
        const expected=previous.value;
        const accuracy=expected.type===r.type && Math.hypot(expected.x-r.x,expected.y-r.y)<24;
        this.verifyClaim(agent,previous.sourceAgentId,state,accuracy,`${previous.key||key}`);
      }
      this.setFact(agent,key,{id:r.id,type:r.type,x:r.x,y:r.y,amountBand:r.amountBand},r.confidence,"direct");
    }

    for(const p of observation.nearbyAgents){
      this.setFact(agent,`agent:${p.id}`,p,.84,"direct");
      if(p.distress)this.setFact(agent,`distress:${p.id}`,p,.95,"direct");
    }

    for(const msg of observation.messages){
      const speaker=state&&state.agentById?state.agentById.get(msg.from):null;
      const localTrust=agent.social.trust.get(msg.from)??.55;
      const trust=clamp(localTrust*.72+(speaker?speaker.social.reputation.credibility:.55)*.28,.05,.98);
      for(const fact of msg.facts){
        const old=agent.mind.facts.get(fact.key);
        const relayedConfidence=clamp(fact.confidence*trust*.92,.12,.88);
        if(!old || relayedConfidence>old.confidence){
          this.setFact(agent,fact.key,fact.value,relayedConfidence,"message",msg.from);
        }
      }
      this.remember(agent,`received ${msg.intent} from Astra-${String(msg.from).padStart(3,"0")}: ${msg.text||"-"} (${msg.facts.length} facts)`,"social");
      agent.social.lastMessage={...msg};
    }

    // If a relayed resource claim says a source should be here, but the observer reaches the location and cannot see it, mark it false.
    const visibleIds=new Set(observation.visibleResources.map(r=>r.id));
    for(const [key,fact] of [...agent.mind.facts]){
      if(!fact.sourceAgentId||!fact.value||!fact.value.id||!RESOURCE_TYPES.includes(fact.value.type))continue;
      const d=Math.hypot(observation.self.x-fact.value.x,observation.self.y-fact.value.y);
      if(d<=Math.min(CONFIG.observationRange*.62,58)&&!visibleIds.has(fact.value.id)){
        this.verifyClaim(agent,fact.sourceAgentId,state,false,key);agent.mind.facts.delete(key);
      }
    }

    // Confidence decay creates stale and fallible beliefs instead of a perfect map.
    if(observation.tick%30===0){
      for(const [key,fact] of agent.mind.facts){
        if(key==="camp:location")continue;
        const age=observation.tick-fact.lastSeenTick;
        fact.confidence=clamp(fact.confidence-(age>100?.018:.004),.08,1);
      }
    }
  }
  learn(agent,outcome){
    agent.runtime.lastOutcome=outcome;
    this.trace(agent,"OUTCOME",`${outcome.actionType}: ${outcome.ok?"OK":"FAIL"} · ${outcome.message}`);
    if(outcome.significant)this.remember(agent,outcome.message,outcome.ok?"success":"failure");
    if(!outcome.ok){
      agent.mind.failedActions++;agent.mind.replanAtTick=this.tickOf(agent);
      if(outcome.actionType===ACTION.GATHER && outcome.resourceId && outcome.invalidateFact){
        agent.mind.facts.delete(`resource:${outcome.resourceId}`);
        agent.mind.target=null;
        this.remember(agent,`invalidated stale resource belief #${outcome.resourceId}: ${outcome.message}`,"learning");
      }
    }
  }
}

class ObservationSystem{
  capture(state,agent){
    const range=agent.role==="scout"?CONFIG.scoutRange:CONFIG.observationRange;
    const visibleResources=[];
    for(const r of state.resources){
      if(r.amount<=.05)continue;
      const d=distance(agent.body,r);
      if(d<=range){
        visibleResources.push(Object.freeze({
          id:r.id,type:r.type,x:round1(r.x),y:round1(r.y),distance:round1(d),
          amountBand:r.amount>r.max*.66?"high":r.amount>r.max*.25?"medium":"low",
          confidence:clamp(1-d/(range*1.45),.48,.98)
        }));
      }
    }
    visibleResources.sort((a,b)=>a.distance-b.distance);

    const nearbyAgents=[];
    for(const other of state.agents){
      if(other.id===agent.id || !other.alive)continue;
      const d=distance(agent.body,other.body);
      if(d<=range){
        nearbyAgents.push(Object.freeze({
          id:other.id,role:other.role,x:round1(other.body.x),y:round1(other.body.y),distance:round1(d),
          hpBand:other.body.hp<35?"critical":other.body.hp<65?"hurt":"stable",
          distress:other.body.hp<45||other.body.thirst>82||other.body.hunger>84
        }));
      }
    }
    nearbyAgents.sort((a,b)=>a.distance-b.distance);

    const campDistance=distance(agent.body,state.camp);
    const campVisible=campDistance<=CONFIG.campSyncRange;
    const messages=agent.social.inbox.splice(0,7).map(m=>Object.freeze({
      id:m.id,from:m.from,to:m.to,intent:m.intent,tick:m.tick,urgency:m.urgency,text:m.text,replyTo:m.replyTo||null,
      facts:m.facts.map(f=>Object.freeze({...f}))
    }));

    return Object.freeze({
      protocol:PROTOCOL.observation,
      observationId:`${state.simulationId}:${state.tick}:${agent.id}`,
      tick:state.tick,
      self:Object.freeze({
        id:agent.id,role:agent.role,x:round1(agent.body.x),y:round1(agent.body.y),hp:round1(agent.body.hp),
        hunger:round1(agent.body.hunger),thirst:round1(agent.body.thirst),energy:round1(agent.body.energy),
        carry:Object.freeze({...agent.inventory})
      }),
      environment:Object.freeze({
        day:state.day,isNight:(state.tick%CONFIG.dayTicks)/CONFIG.dayTicks>.68,
        stormActive:state.stormTicks>0,stormTicks:state.stormTicks
      }),
      camp:Object.freeze({
        x:state.camp.x,y:state.camp.y,distance:round1(campDistance),visible:campVisible,
        stock:campVisible?Object.freeze({...state.stock}):null,
        shelter:campVisible?state.camp.shelter:null,
        construction:campVisible?Object.freeze({...state.camp.construction}):null
      }),
      visibleResources:Object.freeze(visibleResources),
      nearbyAgents:Object.freeze(nearbyAgents),
      messages:Object.freeze(messages)
    });
  }
}


class ObservationContract{
  schema(){
    return {
      "$schema":"https://json-schema.org/draft/2020-12/schema",
      "$id":PROTOCOL.observation,
      type:"object",
      additionalProperties:false,
      required:["protocol","observationId","tick","self","environment","camp","visibleResources","nearbyAgents","messages"],
      properties:{
        protocol:{const:PROTOCOL.observation},observationId:{type:"string"},tick:{type:"integer",minimum:0},
        self:{type:"object",required:["id","role","x","y","hp","hunger","thirst","energy","carry"]},
        environment:{type:"object",required:["day","isNight","stormActive","stormTicks"]},
        camp:{type:"object",required:["x","y","distance","visible","stock","shelter","construction"]},
        visibleResources:{type:"array",items:{type:"object",required:["id","type","x","y","distance","amountBand","confidence"]}},
        nearbyAgents:{type:"array",items:{type:"object",required:["id","role","x","y","distance","hpBand","distress"]}},
        messages:{type:"array",items:{type:"object",required:["id","from","to","intent","tick","urgency","text","replyTo","facts"]}}
      }
    };
  }
  validate(obs){
    const errors=[];const need=(ok,msg)=>{if(!ok)errors.push(msg)};
    need(isPlainObject(obs),"observation must be a plain object");
    if(!isPlainObject(obs))return {ok:false,errors};
    need(obs.protocol===PROTOCOL.observation,"protocol mismatch");
    need(typeof obs.observationId==="string"&&obs.observationId.length>3,"observationId missing");
    need(Number.isInteger(obs.tick)&&obs.tick>=0,"tick invalid");
    need(isPlainObject(obs.self),"self invalid");
    if(isPlainObject(obs.self)){
      need(Number.isInteger(obs.self.id)&&obs.self.id>0,"self.id invalid");
      need(typeof obs.self.role==="string","self.role invalid");
      for(const key of ["x","y","hp","hunger","thirst","energy"])need(finite(obs.self[key]),`self.${key} invalid`);
      need(isPlainObject(obs.self.carry),"self.carry invalid");
    }
    need(isPlainObject(obs.environment),"environment invalid");
    need(isPlainObject(obs.camp),"camp invalid");
    need(Array.isArray(obs.visibleResources),"visibleResources invalid");
    if(Array.isArray(obs.visibleResources))for(const [index,r] of obs.visibleResources.entries()){
      need(isPlainObject(r),`visibleResources[${index}] invalid`);if(!isPlainObject(r))continue;
      need(Number.isInteger(r.id)&&r.id>0,`visibleResources[${index}].id invalid`);
      need(RESOURCE_TYPES.includes(r.type),`visibleResources[${index}].type invalid`);
      for(const key of ["x","y","distance","confidence"])need(finite(r[key]),`visibleResources[${index}].${key} invalid`);
    }
    need(Array.isArray(obs.nearbyAgents),"nearbyAgents invalid");
    if(Array.isArray(obs.nearbyAgents))for(const [index,a] of obs.nearbyAgents.entries()){
      need(isPlainObject(a),`nearbyAgents[${index}] invalid`);if(!isPlainObject(a))continue;
      need(Number.isInteger(a.id)&&a.id>0,`nearbyAgents[${index}].id invalid`);
      for(const key of ["x","y","distance"])need(finite(a[key]),`nearbyAgents[${index}].${key} invalid`);
    }
    need(Array.isArray(obs.messages),"messages invalid");
    if(Array.isArray(obs.messages))for(const [index,m] of obs.messages.entries()){
      need(isPlainObject(m),`messages[${index}] invalid`);if(!isPlainObject(m))continue;
      need(Number.isInteger(m.from)&&m.from>0,`messages[${index}].from invalid`);
      need(SOCIAL_INTENTS.includes(m.intent),`messages[${index}].intent invalid`);
      need(finite(m.urgency)&&m.urgency>=0&&m.urgency<=1,`messages[${index}].urgency invalid`);
      need(typeof m.text==="string"&&m.text.length<=180,`messages[${index}].text invalid`);
      need(Array.isArray(m.facts),`messages[${index}].facts invalid`);
    }
    return {ok:errors.length===0,errors:errors.slice(0,24)};
  }
}

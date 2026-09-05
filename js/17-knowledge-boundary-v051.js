(() => {
  "use strict";

  const PUBLIC_KNOWLEDGE_V051=Object.freeze({
    campLocation:true,
    basicActionRules:true,
    globalAliveCount:false,
    remoteCampStock:false,
    globalReputation:false,
    resourceLocations:false,
    exactStormRemaining:false
  });

  const oldCapture=ObservationSystem.prototype.capture;
  ObservationSystem.prototype.capture=function(state,agent){
    const obs=cloneJson(oldCapture.call(this,state,agent));
    obs.environment.stormTicks=null;
    obs.environment.stormBand=obs.environment.stormActive?"ACTIVE":"CLEAR";
    return deepFreeze(obs);
  };

  const oldBuild=DecisionRequestFactory.prototype.build;
  DecisionRequestFactory.prototype.build=function(state,agent,observation,providerHint){
    const request=cloneJson(oldBuild.call(this,state,agent,observation,providerHint));
    request.simulation.alive=1+(observation.nearbyAgents?.length||0);
    request.simulation.populationScope="LOCAL_VISIBLE_ESTIMATE";
    return deepFreeze(request);
  };

  const oldPrepare=DecisionRouter.prototype.prepare;
  DecisionRouter.prototype.prepare=function(state,packet,summary){
    const visibleAlive=1+(packet.observation?.nearbyAgents?.length||0);
    return oldPrepare.call(this,state,packet,{alive:visibleAlive,scope:"LOCAL_VISIBLE_ESTIMATE"});
  };

  MemorySystem.prototype.ingest=function(agent,observation,state=null){
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
      if(previous&&previous.sourceAgentId){
        const expected=previous.value;
        const accuracy=expected.type===r.type&&Math.hypot(expected.x-r.x,expected.y-r.y)<24;
        this.verifyClaim(agent,previous.sourceAgentId,state,accuracy,`${previous.key||key}`);
      }
      this.setFact(agent,key,{id:r.id,type:r.type,x:r.x,y:r.y,amountBand:r.amountBand},r.confidence,"direct");
    }

    for(const p of observation.nearbyAgents){
      this.setFact(agent,`agent:${p.id}`,p,.84,"direct");
      if(p.distress)this.setFact(agent,`distress:${p.id}`,p,.95,"direct");
    }

    for(const msg of observation.messages){
      const localTrust=agent.social.trust.get(msg.from)??.55;
      const trust=clamp(localTrust,.05,.98);
      for(const fact of msg.facts){
        const old=agent.mind.facts.get(fact.key);
        const relayedConfidence=clamp(fact.confidence*trust*.92,.12,.88);
        if(!old||relayedConfidence>old.confidence)this.setFact(agent,fact.key,fact.value,relayedConfidence,"message",msg.from);
      }
      this.remember(agent,`received ${msg.intent} from Astra-${String(msg.from).padStart(3,"0")}: ${msg.text||"-"} (${msg.facts.length} facts)`,"social");
      agent.social.lastMessage={...msg};
    }

    const visibleIds=new Set(observation.visibleResources.map(r=>r.id));
    for(const [key,fact] of [...agent.mind.facts]){
      if(!fact.sourceAgentId||!fact.value||!fact.value.id||!RESOURCE_TYPES.includes(fact.value.type))continue;
      const d=Math.hypot(observation.self.x-fact.value.x,observation.self.y-fact.value.y);
      if(d<=Math.min(CONFIG.observationRange*.62,58)&&!visibleIds.has(fact.value.id)){
        this.verifyClaim(agent,fact.sourceAgentId,state,false,key);agent.mind.facts.delete(key);
      }
    }

    if(observation.tick%30===0){
      for(const [key,fact] of agent.mind.facts){
        if(key==="camp:location")continue;
        const age=observation.tick-fact.lastSeenTick;
        fact.confidence=clamp(fact.confidence-(age>100?.018:.004),.08,1);
      }
    }
  };

  const oldBundle=WorldRuntime.prototype.contractBundle;
  WorldRuntime.prototype.contractBundle=function(){
    return {...oldBundle.call(this),knowledgeBoundary:{version:"p0.1",publicKnowledge:PUBLIC_KNOWLEDGE_V051,rule:"Agent cognition may consume only immutable observation, owned memory/belief, and delivered messages. Evaluation-only world metrics are not cognitive inputs."}};
  };

  window.AstraLifeKnowledgeBoundary=Object.freeze({
    version:"p0.1",
    publicKnowledge:PUBLIC_KNOWLEDGE_V051,
    rule:"OBSERVATION + OWNED MEMORY + DELIVERED MESSAGES ONLY"
  });
})();

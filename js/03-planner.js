class Planner{
  constructor(rng,memory){this.rng=rng;this.memory=memory}
  setGoal(agent,goal,reason){
    if(agent.mind.goal!==goal){
      agent.mind.goal=goal;agent.mind.goalReason=reason;agent.mind.target=null;
      agent.mind.plan=`${goal.toUpperCase()} ← ${reason}`;
      this.memory.trace(agent,"PLAN",agent.mind.plan);
    }
  }
  factTargets(agent,type){
    return [...agent.mind.facts.values()]
      .filter(f=>f.value&&f.value.type===type&&f.confidence>.18)
      .sort((a,b)=>{
        const da=Math.hypot(agent.body.x-a.value.x,agent.body.y-a.value.y);
        const db=Math.hypot(agent.body.x-b.value.x,agent.body.y-b.value.y);
        return da-db || b.confidence-a.confidence;
      });
  }
  chooseGoal(agent,obs,stateSummary){
    const self=obs.self;
    if(agent.inventory.amount>=agent.capacity*.8)return this.setGoal(agent,"return_camp","inventory nearly full");
    if(self.thirst>82)return this.setGoal(agent,"drink","critical thirst");
    if(self.hunger>84)return this.setGoal(agent,"eat","critical hunger");
    if(self.hp<38)return this.setGoal(agent,"seek_healer","critical health");
    if(self.energy<16)return this.setGoal(agent,"rest","low energy");

    const hurt=obs.nearbyAgents.find(p=>p.hpBand!=="stable");
    if(agent.role==="healer"&&hurt){agent.mind.targetAgentId=hurt.id;return this.setGoal(agent,"heal_peer",`nearby ${hurt.hpBand} peer`)}

    const stock=agent.mind.beliefStock;
    const sheltersKnown=obs.camp.visible?obs.camp.shelter:agent.mind.knownShelters;
    if(obs.camp.visible)agent.mind.knownShelters=obs.camp.shelter;
    const desiredShelters=Math.ceil(stateSummary.alive/12);

    if(agent.role==="builder"&&sheltersKnown<desiredShelters&&stock.wood>=CONFIG.buildWoodCost)
      return this.setGoal(agent,"build_shelter","camp has wood and shelter deficit");
    if(stock.water<28)return this.setGoal(agent,"fetch_water","communal water shortage");
    if(stock.food<28)return this.setGoal(agent,"gather_food","communal food shortage");
    if(sheltersKnown<desiredShelters&&stock.wood<CONFIG.buildWoodCost)
      return this.setGoal(agent,"gather_wood","shelter needs construction material");

    if(agent.role==="scout"&&this.rng.chance(.64))return this.setGoal(agent,"explore","role preference: map unknown space");
    if(agent.role==="carrier")return this.setGoal(agent,this.rng.chance(.55)?"fetch_water":"gather_food","role preference: logistics");
    if(agent.role==="gatherer")return this.setGoal(agent,this.rng.chance(.58)?"gather_food":"gather_wood","role preference: gathering");
    if(agent.role==="builder")return this.setGoal(agent,"gather_wood","role preference: prepare construction");
    return this.setGoal(agent,this.rng.chance(.30)?"explore":"help_network","no urgent local task");
  }
  socialPayload(agent,intent,facts=[],extra={}){
    return {intent,targetAgentId:extra.targetAgentId||null,replyTo:extra.replyTo||null,urgency:clamp(extra.urgency??.45,0,1),text:String(extra.text||"").slice(0,180),facts:facts.slice(0,5)};
  }
  maybeCommunicate(agent,obs,queue){
    if(agent.mind.communicationCooldown>obs.tick || !obs.nearbyAgents.length)return false;
    const incoming=obs.messages[0];
    if(incoming&&(incoming.intent==="ASK"||incoming.intent==="REQUEST_HELP")){
      const wanted=(incoming.text.match(/water|food|berry|wood|tree|herb/i)||[])[0];
      const type=wanted==="food"?"berry":wanted==="wood"?"tree":wanted;
      const facts=type?[...agent.mind.facts.values()].filter(f=>f.value&&f.value.type===type).sort((a,b)=>b.confidence-a.confidence).slice(0,3).map(f=>({key:f.key,value:{...f.value},confidence:f.confidence})):[ ];
      if(facts.length||agent.role==="healer"){
        const intent=incoming.intent==="REQUEST_HELP"?"OFFER":"REPORT";
        queue.enqueue(obs.tick,agent.id,ACTION.SHARE,this.socialPayload(agent,intent,facts,{targetAgentId:incoming.from,replyTo:incoming.id,urgency:.72,text:facts.length?`I can report ${type||"useful"} information`:`I can help; I am a ${agent.role}`}),"respond to peer message");
        agent.mind.communicationCooldown=obs.tick+CONFIG.socialCooldownMin;return true;
      }
    }
    if(obs.environment.stormActive && obs.tick-agent.social.lastWarningTick>95){
      queue.enqueue(obs.tick,agent.id,ACTION.SHARE,this.socialPayload(agent,"WARN",[],{urgency:.92,text:"Storm active: return toward camp and shelter"}),"warn nearby peers about immediate environmental risk");
      agent.social.lastWarningTick=obs.tick;agent.mind.communicationCooldown=obs.tick+28;return true;
    }
    if((obs.self.thirst>78||obs.self.hunger>80||obs.self.hp<42) && obs.tick-agent.social.lastHelpRequestTick>65){
      const need=obs.self.hp<42?"medical help":obs.self.thirst>78?"water":"food";
      queue.enqueue(obs.tick,agent.id,ACTION.SHARE,this.socialPayload(agent,"REQUEST_HELP",[],{urgency:.96,text:`Need ${need}; location ${Math.round(obs.self.x)},${Math.round(obs.self.y)}`}),"request survival assistance");
      agent.social.lastHelpRequestTick=obs.tick;agent.mind.communicationCooldown=obs.tick+26;return true;
    }
    const keys=agent.mind.newFactKeys.slice(0,4);
    if(keys.length){
      const facts=keys.map(key=>agent.mind.facts.get(key)).filter(Boolean).map(f=>({key:f.key,value:{...f.value},confidence:f.confidence}));
      if(facts.length){queue.enqueue(obs.tick,agent.id,ACTION.SHARE,this.socialPayload(agent,"REPORT",facts,{urgency:.55,text:`New observations: ${facts.map(f=>f.value.type||f.key).join(", ")}`}),"report fresh observations to peers");agent.mind.newFactKeys.length=0;agent.mind.communicationCooldown=obs.tick+CONFIG.socialCooldownMin+this.rng.int(0,CONFIG.socialCooldownMax-CONFIG.socialCooldownMin);return true}
    }
    return false;
  }
  queueAskFor(agent,obs,queue,type){
    if(!obs.nearbyAgents.length||agent.mind.communicationCooldown>obs.tick)return false;
    queue.enqueue(obs.tick,agent.id,ACTION.SHARE,this.socialPayload(agent,"ASK",[],{urgency:.58,text:`Does anyone know a reliable ${type} source?`}),`ask peers for ${type} knowledge`);
    agent.mind.communicationCooldown=obs.tick+32;return true;
  }
  queueMove(agent,obs,queue,target,reason,speed=1){
    agent.mind.target={x:target.x,y:target.y};
    agent.mind.plan=`MOVE(${Math.round(target.x)},${Math.round(target.y)}) → ${reason}`;
    queue.enqueue(obs.tick,agent.id,ACTION.MOVE,{x:target.x,y:target.y,speed},reason);
  }
  planResourcePipeline(agent,obs,queue,resourceType,carryType){
    if(agent.inventory.amount>0 && agent.inventory.type!==carryType){
      this.setGoal(agent,"return_camp","carrying a different resource");
      return this.queueMove(agent,obs,queue,obs.camp,"return to communal stock",1.05);
    }
    if(agent.inventory.amount>=agent.capacity*.8){
      this.setGoal(agent,"return_camp","load ready for deposit");
      return this.queueMove(agent,obs,queue,obs.camp,"deposit carried resource",1.08);
    }
    const targetFact=this.factTargets(agent,resourceType)[0];
    if(!targetFact){
      if(this.queueAskFor(agent,obs,queue,resourceType))return;
      this.setGoal(agent,"explore",`no known ${resourceType} source`);
      return this.planExplore(agent,obs,queue);
    }
    const target=targetFact.value;
    const d=Math.hypot(obs.self.x-target.x,obs.self.y-target.y);
    if(d<=CONFIG.interactRange){
      agent.mind.plan=`GATHER ${resourceType}#${target.id} → carry ${carryType}`;
      queue.enqueue(obs.tick,agent.id,ACTION.GATHER,{resourceId:target.id,resourceType,carryType},`harvest known ${resourceType}`);
    }else this.queueMove(agent,obs,queue,target,`reach known ${resourceType}`,1.05);
  }
  planExplore(agent,obs,queue){
    let target=agent.mind.exploreTarget;
    if(!target || Math.hypot(obs.self.x-target.x,obs.self.y-target.y)<16 || obs.tick-agent.mind.exploreTargetTick>110){
      const angle=this.rng.float(0,Math.PI*2);
      const radius=this.rng.float(135,410);
      target={x:clamp(obs.camp.x+Math.cos(angle)*radius,18,SPACE.width-18),y:clamp(obs.camp.y+Math.sin(angle)*radius,18,SPACE.height-18)};
      agent.mind.exploreTarget=target;agent.mind.exploreTargetTick=obs.tick;
      this.memory.remember(agent,`selected exploration waypoint ${Math.round(target.x)},${Math.round(target.y)}`,"plan");
    }
    this.queueMove(agent,obs,queue,target,"explore and update symbolic map",agent.role==="scout"?1.18:.92);
  }
  decide(agent,obs,queue,stateSummary){
    if(!agent.alive)return;
    if(agent.mind.replanAtTick<=obs.tick || agent.mind.goal==="orient"){
      this.chooseGoal(agent,obs,stateSummary);
      agent.mind.replanAtTick=obs.tick+18+this.rng.int(0,14);
    }

    if(this.maybeCommunicate(agent,obs,queue)){
      agent.runtime.lastActionType=ACTION.SHARE;
      this.memory.trace(agent,"ACTION",`SOCIAL · ${agent.mind.goal}`);
      return;
    }

    switch(agent.mind.goal){
      case "drink":
        if((agent.inventory.type==="water"&&agent.inventory.amount>=1)||(obs.camp.visible&&obs.camp.stock.water>=1))
          queue.enqueue(obs.tick,agent.id,ACTION.CONSUME,{resource:"water"},"satisfy critical thirst");
        else this.planResourcePipeline(agent,obs,queue,"water","water");
        break;
      case "eat":
        if((agent.inventory.type==="food"&&agent.inventory.amount>=1)||(obs.camp.visible&&obs.camp.stock.food>=1))
          queue.enqueue(obs.tick,agent.id,ACTION.CONSUME,{resource:"food"},"satisfy critical hunger");
        else this.planResourcePipeline(agent,obs,queue,"berry","food");
        break;
      case "fetch_water":this.planResourcePipeline(agent,obs,queue,"water","water");break;
      case "gather_food":this.planResourcePipeline(agent,obs,queue,"berry","food");break;
      case "gather_wood":this.planResourcePipeline(agent,obs,queue,"tree","wood");break;
      case "return_camp":
        if(obs.camp.distance<=CONFIG.campSyncRange)queue.enqueue(obs.tick,agent.id,ACTION.DEPOSIT,{},"commit cargo to communal stock");
        else this.queueMove(agent,obs,queue,obs.camp,"return to camp",1.08);
        break;
      case "build_shelter":
        if(obs.camp.distance>42)this.queueMove(agent,obs,queue,obs.camp,"join construction crew",1.0);
        else queue.enqueue(obs.tick,agent.id,ACTION.BUILD,{},"contribute labor to shared shelter");
        break;
      case "heal_peer":{
        const target=obs.nearbyAgents.find(p=>p.id===agent.mind.targetAgentId);
        if(!target){agent.mind.replanAtTick=obs.tick;queue.enqueue(obs.tick,agent.id,ACTION.WAIT,{},"patient no longer visible");break}
        if(target.distance<=CONFIG.interactRange+4)queue.enqueue(obs.tick,agent.id,ACTION.HEAL,{targetAgentId:target.id},"treat nearby injured peer");
        else this.queueMove(agent,obs,queue,target,"reach injured peer",1.07);
        break;
      }
      case "seek_healer":{
        const healer=obs.nearbyAgents.find(p=>p.role==="healer");
        if(healer)this.queueMove(agent,obs,queue,healer,"seek nearby healer",.88);
        else this.queueMove(agent,obs,queue,obs.camp,"seek help at camp",.82);
        break;
      }
      case "rest":
        if(obs.camp.distance>55)this.queueMove(agent,obs,queue,obs.camp,"rest within camp safety",.72);
        else queue.enqueue(obs.tick,agent.id,ACTION.REST,{},"recover energy");
        break;
      case "help_network":
        if(obs.nearbyAgents.length && obs.nearbyAgents[0].distance>58)this.queueMove(agent,obs,queue,obs.nearbyAgents[0],"join nearest knowledge network",.78);
        else {
          const facts=[...agent.mind.facts.values()].sort((a,b)=>b.confidence-a.confidence).slice(0,2).map(f=>({key:f.key,value:{...f.value},confidence:f.confidence}));
          queue.enqueue(obs.tick,agent.id,ACTION.SHARE,this.socialPayload(agent,"OFFER",facts,{urgency:.35,text:"I can share useful local knowledge"}),"offer knowledge to nearby peers");
        }
        break;
      case "explore":default:this.planExplore(agent,obs,queue);break;
    }
    const queued=queue.items[queue.items.length-1];
    agent.runtime.lastActionType=queued&&queued.agentId===agent.id?queued.type:ACTION.WAIT;
    this.memory.trace(agent,"ACTION",`${agent.runtime.lastActionType} · goal=${agent.mind.goal}`);
  }
}

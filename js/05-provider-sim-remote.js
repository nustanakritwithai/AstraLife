class AstraCompatibleSimulatorProvider{
  constructor(){this.id="astra-sim"}
  factTargets(request,type){
    const x=request.observation.self.x,y=request.observation.self.y;
    return request.memory.symbolicFacts.filter(f=>f.value&&f.value.type===type&&f.confidence>.18)
      .sort((a,b)=>Math.hypot(x-a.value.x,y-a.value.y)-Math.hypot(x-b.value.x,y-b.value.y)||b.confidence-a.confidence);
  }
  response(request,goal,reason,plan,type,payload={},confidence=.82,replan=22,thoughts=[]){
    return makeDecisionResponse(request,this.id,{type,payload,reason},{goal,reason,plan},confidence,replan,{engine:"contract-only-astra-simulator",deliberation:thoughts.slice(0,8)});
  }
  explore(request,goal,reason,thoughts){
    const rng=new SeededRandom(`${request.simulation.seed}|${request.agent.id}|${Math.floor(request.simulation.tick/86)}`);
    const angle=rng.float(0,Math.PI*2),radius=rng.float(150,430),camp=request.observation.camp;
    const target={x:clamp(camp.x+Math.cos(angle)*radius,18,SPACE.width-18),y:clamp(camp.y+Math.sin(angle)*radius,18,SPACE.height-18)};
    thoughts.push("No dependable target fact; generate bounded exploration waypoint.");
    return this.response(request,goal,reason,`MOVE(${Math.round(target.x)},${Math.round(target.y)}) → OBSERVE → REPORT`,ACTION.MOVE,{x:target.x,y:target.y,speed:request.agent.role==="scout"?1.18:.92},.72,28,thoughts);
  }
  resourcePipeline(request,goal,reason,resourceType,carryType,thoughts){
    const o=request.observation,carry=o.self.carry;
    if(carry.amount>0&&carry.type!==carryType){
      thoughts.push("Inventory conflict; protect existing cargo and return to camp.");
      return this.response(request,"return_camp","carrying a different resource","RETURN → DEPOSIT",ACTION.MOVE,{x:o.camp.x,y:o.camp.y,speed:1.06},.9,12,thoughts);
    }
    if(carry.amount>=request.agent.capacity*.8){
      if(o.camp.distance<=CONFIG.campSyncRange)return this.response(request,"return_camp","load ready for communal deposit","DEPOSIT",ACTION.DEPOSIT,{},.95,10,thoughts);
      return this.response(request,"return_camp","load ready for communal deposit","MOVE CAMP → DEPOSIT",ACTION.MOVE,{x:o.camp.x,y:o.camp.y,speed:1.08},.92,10,thoughts);
    }
    const target=this.factTargets(request,resourceType)[0];
    if(!target)return this.explore(request,"explore",`no trusted ${resourceType} fact`,thoughts);
    const d=Math.hypot(o.self.x-target.value.x,o.self.y-target.value.y);
    thoughts.push(`Selected ${resourceType} fact ${target.key} at confidence ${target.confidence}.`);
    if(d<=CONFIG.interactRange)return this.response(request,goal,reason,`GATHER ${resourceType}#${target.value.id} → CARRY ${carryType}`,ACTION.GATHER,{resourceId:target.value.id,resourceType,carryType},.88,14,thoughts);
    return this.response(request,goal,reason,`MOVE → ${resourceType}#${target.value.id} → GATHER`,ACTION.MOVE,{x:target.value.x,y:target.value.y,speed:1.05},.84,18,thoughts);
  }
  decide(request){
    const o=request.observation,m=request.memory,a=request.agent,thoughts=[];
    const carry=o.self.carry,stock=o.camp.stock||m.beliefStock||{food:0,water:0,wood:0,medicine:0};
    const desiredShelters=Math.ceil(request.simulation.alive/12),knownShelters=o.camp.visible?(o.camp.shelter||0):(m.knownShelters||0);
    const recentFacts=m.symbolicFacts.filter(f=>f.lastSeenTick>=request.simulation.tick-3&&f.confidence>.62).slice(0,4);

    if(o.nearbyAgents.length&&recentFacts.length&&((request.simulation.tick+a.id)%43===0)){
      thoughts.push("Fresh facts and reachable peers detected; information propagation has high group value.");
      return this.response(request,m.currentGoal||"help_network","broadcast fresh observations","REPORT facts → peers",ACTION.SHARE,{intent:"REPORT",facts:recentFacts.map(f=>({key:f.key,value:f.value,confidence:f.confidence}))},.86,18,thoughts);
    }
    if(carry.amount>=a.capacity*.8){
      thoughts.push("Cargo threshold reached; prevent loss and reinforce communal stock.");
      if(o.camp.distance<=CONFIG.campSyncRange)return this.response(request,"return_camp","inventory nearly full","DEPOSIT",ACTION.DEPOSIT,{},.96,8,thoughts);
      return this.response(request,"return_camp","inventory nearly full","MOVE CAMP → DEPOSIT",ACTION.MOVE,{x:o.camp.x,y:o.camp.y,speed:1.08},.94,8,thoughts);
    }
    if(o.self.thirst>82){
      thoughts.push("Critical thirst overrides strategic goals.");
      if((carry.type==="water"&&carry.amount>=1)||(o.camp.visible&&o.camp.stock.water>=1))return this.response(request,"drink","critical thirst","CONSUME water",ACTION.CONSUME,{resource:"water"},.99,8,thoughts);
      return this.resourcePipeline(request,"drink","critical thirst","water","water",thoughts);
    }
    if(o.self.hunger>84){
      thoughts.push("Critical hunger overrides strategic goals.");
      if((carry.type==="food"&&carry.amount>=1)||(o.camp.visible&&o.camp.stock.food>=1))return this.response(request,"eat","critical hunger","CONSUME food",ACTION.CONSUME,{resource:"food"},.99,8,thoughts);
      return this.resourcePipeline(request,"eat","critical hunger","berry","food",thoughts);
    }
    if(o.self.hp<38){
      const healer=o.nearbyAgents.find(p=>p.role==="healer");thoughts.push("Health is critical; prioritize reachable care or camp safety.");
      if(healer)return this.response(request,"seek_healer","critical health",`MOVE → healer#${healer.id}`,ACTION.MOVE,{x:healer.x,y:healer.y,speed:.88},.91,12,thoughts);
      return this.response(request,"seek_healer","critical health","MOVE CAMP → request care",ACTION.MOVE,{x:o.camp.x,y:o.camp.y,speed:.82},.86,12,thoughts);
    }
    if(o.self.energy<16){
      thoughts.push("Energy below safe planning threshold.");
      if(o.camp.distance<=55)return this.response(request,"rest","low energy","REST at camp",ACTION.REST,{},.95,12,thoughts);
      return this.response(request,"rest","low energy","MOVE CAMP → REST",ACTION.MOVE,{x:o.camp.x,y:o.camp.y,speed:.72},.9,12,thoughts);
    }
    const hurt=o.nearbyAgents.find(p=>p.hpBand!=="stable");
    if(a.role==="healer"&&hurt){
      thoughts.push("Healer capability and injured peer detected.");
      if(hurt.distance<=CONFIG.interactRange+4)return this.response(request,"heal_peer",`nearby ${hurt.hpBand} peer`,`HEAL agent#${hurt.id}`,ACTION.HEAL,{targetAgentId:hurt.id},.96,10,thoughts);
      return this.response(request,"heal_peer",`nearby ${hurt.hpBand} peer`,`MOVE → agent#${hurt.id} → HEAL`,ACTION.MOVE,{x:hurt.x,y:hurt.y,speed:1.07},.91,10,thoughts);
    }
    if(a.role==="builder"&&knownShelters<desiredShelters&&stock.wood>=CONFIG.buildWoodCost){
      thoughts.push("Shelter deficit and sufficient communal wood detected.");
      if(o.camp.distance<=42)return this.response(request,"build_shelter","camp has wood and shelter deficit","BUILD with crew",ACTION.BUILD,{},.91,18,thoughts);
      return this.response(request,"build_shelter","camp has wood and shelter deficit","MOVE CAMP → BUILD",ACTION.MOVE,{x:o.camp.x,y:o.camp.y,speed:1},.88,18,thoughts);
    }
    if(stock.water<28){thoughts.push("Believed communal water is below reserve target.");return this.resourcePipeline(request,"fetch_water","communal water shortage","water","water",thoughts)}
    if(stock.food<28){thoughts.push("Believed communal food is below reserve target.");return this.resourcePipeline(request,"gather_food","communal food shortage","berry","food",thoughts)}
    if(knownShelters<desiredShelters&&stock.wood<CONFIG.buildWoodCost){thoughts.push("Shelter deficit requires material acquisition.");return this.resourcePipeline(request,"gather_wood","shelter needs construction material","tree","wood",thoughts)}
    if(a.role==="carrier")return this.resourcePipeline(request,"fetch_water","logistics role preference","water","water",thoughts);
    if(a.role==="gatherer")return this.resourcePipeline(request,"gather_food","gathering role preference","berry","food",thoughts);
    if(a.role==="builder")return this.resourcePipeline(request,"gather_wood","prepare future construction","tree","wood",thoughts);
    if(a.role==="scout")return this.explore(request,"explore","scout maps unknown space",thoughts);
    if(o.nearbyAgents.length){
      const facts=m.symbolicFacts.slice(0,2).map(f=>({key:f.key,value:f.value,confidence:f.confidence}));
      if(facts.length)return this.response(request,"help_network","no urgent task; synchronize beliefs","SYNC facts",ACTION.SHARE,{intent:"SYNC",facts},.7,22,thoughts);
    }
    return this.explore(request,"explore","no urgent local task",thoughts);
  }
}

class RemoteHttpProvider{
  constructor(endpointGetter){this.id="remote";this.endpointGetter=endpointGetter}
  isConfigured(){return !!String(this.endpointGetter()||"").trim()}
  async decide(request){
    const endpoint=String(this.endpointGetter()||"").trim();
    if(!endpoint)throw new Error("Astra HTTP Bridge endpoint is empty");
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),CONFIG.providerTimeoutMs);
    try{
      const response=await fetch(endpoint,{method:"POST",headers:{"content-type":"application/json","accept":"application/json"},body:JSON.stringify(request),signal:controller.signal,credentials:"omit",cache:"no-store",referrerPolicy:"no-referrer"});
      const text=await response.text();
      if(text.length>CONFIG.maxRemoteResponseBytes)throw new Error(`provider response exceeds ${CONFIG.maxRemoteResponseBytes} bytes`);
      if(!response.ok)throw new Error(`provider HTTP ${response.status}: ${text.slice(0,180)}`);
      let data;try{data=JSON.parse(text)}catch(error){throw new Error(`provider returned invalid JSON: ${error.message}`)}
      return data;
    }finally{clearTimeout(timer)}
  }
}

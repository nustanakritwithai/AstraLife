class WorldRuntime{
  constructor(seed){
    this.seed=String(seed||"ASTRA-2026");this.rng=new SeededRandom(this.seed);
    this.events=new EventStore();this.queue=new ActionQueue();this.memory=new MemorySystem();
    this.observer=new ObservationSystem();this.observationContract=new ObservationContract();this.planner=new Planner(this.rng,this.memory);
    this.requestFactory=new DecisionRequestFactory();this.validator=new ActionContractValidator();this.registry=new ProviderRegistry();this.providerEndpoint="";
    this.registry.register("local",new LocalPlannerProvider(this.planner),{label:"Local deterministic brain",kind:"builtin",async:false});
    this.registry.register("astra-sim",new AstraCompatibleSimulatorProvider(),{label:"Astra-compatible simulator",kind:"builtin",async:false});
    this.registry.register("remote",new RemoteHttpProvider(()=>this.providerEndpoint),{label:"Astra HTTP Bridge",kind:"builtin",async:true});
    this.decisionRouter=new DecisionRouter(this.registry,this.requestFactory,this.validator,this.memory,this.events);
    this.resolver=new ActionResolver(this.memory,this.events);this.environment=new EnvironmentSystem(this.events);
    this.phase="COMMIT";this.phaseIndex=7;this.state=null;this.selectedAgentId=null;
    this.reset(this.seed);
  }
  blankState(){
    return {
      simulationId:`sim-${hashSeed(this.seed).toString(16).padStart(8,"0")}`,seed:this.seed,
      tick:0,time:0,day:1,running:true,speed:1,stormTicks:0,nextAgentId:1,nextMessageId:1,
      stock:{food:24,water:24,wood:5,medicine:2.5},
      camp:{x:SPACE.width*.5,y:SPACE.height*.52,r:25,shelter:0,construction:{active:false,progress:0,startedTick:0,crew:[]}},
      terrain:[],resources:[],resourceById:new Map(),agents:[],agentById:new Map(),
      effects:{messages:[]},
      metrics:{deaths:0,structures:0,totalActions:0,failedActions:0,cooperativeActions:0,lastActionCount:0,lastDepositEventTick:-999,observationContractErrors:0,socialMessages:0,intentCounts:{ASK:0,REPORT:0,REQUEST_HELP:0,OFFER:0,WARN:0,SYNC:0},actionCounts:{GATHER:0,DEPOSIT:0,HEAL:0,SHARE:0,BUILD:0}}
    };
  }
  reset(seed=this.seed){
    this.seed=String(seed||"ASTRA-2026");this.rng=new SeededRandom(this.seed);this.planner.rng=this.rng;
    this.events=new EventStore();this.resolver.events=this.events;this.environment.events=this.events;
    this.queue=new ActionQueue();this.state=this.blankState();this.selectedAgentId=null;this.decisionRouter.reset(this.events);
    this.generateTerrain();this.generateResources();this.spawnAgents(CONFIG.initialAgents);
    this.events.emit(0,"WORLD_RESET",`สร้างโลก V0.4 ด้วย seed “${this.seed}” · Agents ${CONFIG.initialAgents} คน · Social ${PROTOCOL.communication}`,{seed:this.seed},"important");
    this.phase="COMMIT";this.phaseIndex=7;
  }
  generateTerrain(){
    const types=["forest","meadow","rock","wetland"];
    for(let i=0;i<22;i++)this.state.terrain.push({x:this.rng.float(0,SPACE.width),y:this.rng.float(0,SPACE.height),r:this.rng.float(60,175),type:this.rng.pick(types)});
  }
  addResource(type,x,y,amount){
    const id=this.state.resources.length+1;const r={id,type,x,y,amount,max:amount};
    this.state.resources.push(r);this.state.resourceById.set(id,r);
  }
  generateResources(){
    for(let i=0;i<18;i++){
      const edge=this.rng.chance(.58);
      const x=edge?(this.rng.chance(.5)?this.rng.float(25,SPACE.width*.22):this.rng.float(SPACE.width*.78,SPACE.width-25)):this.rng.float(35,SPACE.width-35);
      this.addResource("water",x,this.rng.float(40,SPACE.height-30),this.rng.float(65,95));
    }
    for(let i=0;i<48;i++)this.addResource("berry",this.rng.float(28,SPACE.width-28),this.rng.float(28,SPACE.height-28),this.rng.float(6,14));
    for(let i=0;i<76;i++)this.addResource("tree",this.rng.float(24,SPACE.width-24),this.rng.float(28,SPACE.height-24),this.rng.float(10,20));
    for(let i=0;i<14;i++)this.addResource("herb",this.rng.float(24,SPACE.width-24),this.rng.float(28,SPACE.height-24),this.rng.float(3,7));
  }
  createAgent(){
    const id=this.state.nextAgentId++;
    const role=this.rng.pick(["scout","gatherer","gatherer","builder","carrier","healer"]);
    const agent={
      id,name:`Astra-${String(id).padStart(3,"0")}`,role,alive:true,capacity:role==="carrier"?4.2:3,
      body:{x:this.state.camp.x+this.rng.float(-48,48),y:this.state.camp.y+this.rng.float(-48,48),hp:100,hunger:this.rng.float(5,25),thirst:this.rng.float(5,25),energy:this.rng.float(72,100),ageTicks:0},
      inventory:{type:null,amount:0},
      mind:{
        goal:"orient",goalReason:"spawned without global knowledge",plan:"OBSERVE → INFER → ACT",target:null,targetAgentId:null,
        facts:new Map(),memory:[],newFactKeys:[],beliefStock:{food:0,water:0,wood:0,medicine:0},knownShelters:0,lastCampSyncTick:-1,
        communicationCooldown:0,replanAtTick:0,exploreTarget:null,exploreTargetTick:0,failedActions:0,
        weights:{self:this.rng.float(.45,.78),group:this.rng.float(.48,.88),explore:this.rng.float(.35,.82)}
      },
      social:{trust:new Map(),inbox:[],lastMessage:null,lastWarningTick:-999,lastHelpRequestTick:-999,reputation:{messagesSent:0,reports:0,helpRequests:0,offers:0,warnings:0,claimsVerified:0,accurateClaims:0,misleadingClaims:0,credibility:.55}},
      runtime:{providerSessionId:`${this.state.simulationId}:agent-${id}`,providerStatus:"idle",lastProvider:"local",lastObservation:null,lastObservationContract:null,lastDecisionRequest:null,lastDecisionResponse:null,lastValidation:null,lastActionType:ACTION.WAIT,lastOutcome:null,trace:[]}
    };
    this.memory.setFact(agent,"camp:location",{x:this.state.camp.x,y:this.state.camp.y,type:"camp"},1,"initial");
    this.memory.remember(agent,"spawned at camp; world map unknown; survival may require cooperation","episode");
    return agent;
  }
  spawnAgents(n){
    for(let i=0;i<n;i++){
      const a=this.createAgent();this.state.agents.push(a);this.state.agentById.set(a.id,a);
    }
    if(this.state.tick>0)this.events.emit(this.state.tick,"SPAWN",`เพิ่ม Astra Agents ${n} คนเข้าสู่โลก`,{count:n},"important");
  }
  setPhase(name,index){this.phase=name;this.phaseIndex=index}
  tickOnce(){
    const state=this.state;state.tick++;this.decisionRouter.cleanup(state);
    this.setPhase("ENVIRONMENT",0);this.environment.update(state);

    this.setPhase("OBSERVE",1);
    const packets=[],invalidAgents=[];
    for(const agent of state.agents){
      if(!agent.alive)continue;
      const observation=this.observer.capture(state,agent),contract=this.observationContract.validate(observation);
      agent.runtime.lastObservationContract=contract;
      if(!contract.ok){state.metrics.observationContractErrors++;invalidAgents.push({agent,errors:contract.errors});this.memory.trace(agent,"OBS",`CONTRACT FAIL · ${contract.errors.join(" | ")}`);continue}
      this.memory.ingest(agent,observation,state);
      this.memory.trace(agent,"OBS",`${observation.protocol} · resources=${observation.visibleResources.length}, peers=${observation.nearbyAgents.length}, messages=${observation.messages.length}`);
      packets.push({agent,observation,planner:this.planner});
    }

    const summary={alive:state.agents.filter(a=>a.alive).length};
    this.setPhase("REQUEST",2);
    const tasks=packets.map(packet=>this.decisionRouter.prepare(state,packet,summary));
    for(const item of invalidAgents)this.queue.enqueue(state.tick,item.agent.id,ACTION.WAIT,{},`invalid observation contract: ${item.errors[0]}`,{provider:"runtime",validated:true});

    this.setPhase("PROVIDER",3);for(const task of tasks)this.decisionRouter.invoke(task);
    this.setPhase("VALIDATE",4);for(const task of tasks)this.decisionRouter.complete(state,task,this.queue);

    this.setPhase("RESOLVE",5);
    const actions=this.queue.drain();state.metrics.lastActionCount=actions.length;state.metrics.totalActions+=actions.length;
    const outcomes=this.resolver.resolve(state,actions);

    this.setPhase("LEARN",6);
    for(const outcome of outcomes){
      const agent=state.agentById.get(outcome.agentId);
      if(agent)this.memory.learn(agent,outcome);
      if(!outcome.ok)state.metrics.failedActions++;
    }

    this.setPhase("COMMIT",7);
    state.effects.messages=state.effects.messages.filter(e=>state.tick-e.bornTick<15);
    if(state.tick%100===0){
      const test=this.selfTest();
      if(!test.ok)this.events.emit(state.tick,"INTEGRITY",`Runtime integrity failed: ${test.errors.join("; ")}`,{},"danger");
    }
    return outcomes;
  }
  runTicks(n){
    const count=clamp(Math.floor(Number(n)||1),1,5000);
    let out=[];for(let i=0;i<count;i++)out=this.tickOnce();return out;
  }
  setProviderMode(mode){this.decisionRouter.setMode(mode);this.events.emit(this.state.tick,"PROVIDER_MODE",`เปลี่ยน Decision Provider เป็น ${this.decisionRouter.label()}`,{mode},"important")}
  setProviderEndpoint(endpoint){this.providerEndpoint=String(endpoint||"").trim();return this.providerEndpoint}
  triggerStorm(){
    this.state.stormTicks=CONFIG.stormDurationTicks;
    this.events.emit(this.state.tick,"STORM",`พายุเริ่มโจมตีเป็นเวลา ${CONFIG.stormDurationTicks} ticks — Shelter และการร่วมมือมีความสำคัญ`,{},"danger");
  }
  injectRumor(agentId=this.selectedAgentId){
    const agent=this.state.agentById.get(agentId);if(!agent||!agent.alive)return {ok:false,error:"select a living agent first"};
    const fakeId=900000+agent.id;const payload={intent:"REPORT",targetAgentId:null,replyTo:null,urgency:.76,text:"I found a rich water source nearby",facts:[{key:`resource:${fakeId}`,value:{id:fakeId,type:"water",x:clamp(agent.body.x+42,10,SPACE.width-10),y:clamp(agent.body.y+18,10,SPACE.height-10),amountBand:"high"},confidence:.93}]};
    const action={id:this.queue.nextId++,tick:this.state.tick,agentId:agent.id,type:ACTION.SHARE,payload:deepFreeze(cloneJson(payload)),reason:"manual rumor stress test",priority:PRIORITY.SHARE,meta:{validated:true,provider:"debug-social"}};
    const outcome=this.resolver.resolve(this.state,[action])[0];this.memory.learn(agent,outcome);this.events.emit(this.state.tick,"RUMOR",`${agent.name} ปล่อยข่าวลือเรื่องแหล่งน้ำปลอม เพื่อทดสอบ Trust`,{agentId:agent.id},"important");return outcome;
  }
  averageCredibility(){const alive=this.state.agents.filter(a=>a.alive);return alive.length?alive.reduce((sum,a)=>sum+a.social.reputation.credibility,0)/alive.length:0}
  verifiedClaims(){return this.state.agents.reduce((sum,a)=>sum+a.social.reputation.claimsVerified,0)}
  unionFactCount(){
    const set=new Set();for(const a of this.state.agents)if(a.alive)for(const key of a.mind.facts.keys())set.add(key);return set.size;
  }
  cooperationRate(){
    return this.state.metrics.totalActions?this.state.metrics.cooperativeActions/this.state.metrics.totalActions*100:0;
  }
  selfTest(){
    const errors=[];const s=this.state;
    for(const [k,v] of Object.entries(s.stock))if(!Number.isFinite(v)||v<-.001)errors.push(`stock.${k}`);
    if(new Set(s.agents.map(a=>a.id)).size!==s.agents.length)errors.push("duplicate agent id");
    if(new Set(s.resources.map(r=>r.id)).size!==s.resources.length)errors.push("duplicate resource id");
    for(const a of s.agents){
      if(!Number.isFinite(a.body.x)||!Number.isFinite(a.body.y))errors.push(`agent ${a.id} position`);
      if(a.inventory.amount<-.001)errors.push(`agent ${a.id} inventory`);
      if(!finite(a.social.reputation.credibility)||a.social.reputation.credibility<0||a.social.reputation.credibility>1)errors.push(`agent ${a.id} credibility`);
      if(a.social.inbox.length>CONFIG.maxSocialInbox)errors.push(`agent ${a.id} social inbox overflow`);
      for(const [peer,t] of a.social.trust)if(!finite(t)||t<0||t>1)errors.push(`agent ${a.id} trust:${peer}`);
    }
    for(const r of s.resources)if(r.amount<-.001||r.amount>r.max+.1)errors.push(`resource ${r.id} amount`);
    for(const a of s.agents)if(a.alive&&a.runtime.lastObservation){const check=this.observationContract.validate(a.runtime.lastObservation);if(!check.ok)errors.push(`agent ${a.id} observation contract`)}
    if(s.metrics.observationContractErrors>0)errors.push(`observation contract errors: ${s.metrics.observationContractErrors}`);
    if(this.queue.items.length)errors.push("unresolved action queue");
    return {ok:errors.length===0,errors};
  }
  contractBundle(){
    return {project:"ASTRA COLONY",version:VERSION,protocols:PROTOCOL,transport:{method:"POST",contentType:"application/json",responseLimitBytes:CONFIG.maxRemoteResponseBytes,timeoutMs:CONFIG.providerTimeoutMs,sessionRule:"Preserve independent state by request.sessionId. Never merge memories between agents."},observationSchema:this.observationContract.schema(),decisionRequestSchema:this.requestFactory.schema(),decisionResponseSchema:this.validator.responseSchema(),actionSchema:this.validator.actionSchema(),communicationSchema:socialCommunicationSchema()};
  }
  snapshot(){
    const s=this.state;
    return {
      metadata:{project:"ASTRA COLONY",version:VERSION,seed:this.seed,simulationId:s.simulationId,exportedAt:new Date().toISOString(),protocols:PROTOCOL},
      provider:{mode:this.decisionRouter.mode,label:this.decisionRouter.label(),endpointConfigured:!!this.providerEndpoint,metrics:cloneJson(this.decisionRouter.metrics),pending:this.decisionRouter.pendingCount(),averageLatencyMs:this.decisionRouter.averageLatency()},
      world:{tick:s.tick,day:s.day,stormTicks:s.stormTicks,stock:{...s.stock},camp:{...s.camp,construction:{...s.camp.construction}}},
      metrics:{...s.metrics,actionCounts:{...s.metrics.actionCounts},knownFacts:this.unionFactCount(),cooperationRate:this.cooperationRate()},
      resources:s.resources.map(r=>({...r})),
      agents:s.agents.map(a=>({
        id:a.id,name:a.name,role:a.role,alive:a.alive,body:{...a.body},inventory:{...a.inventory},
        mind:{goal:a.mind.goal,goalReason:a.mind.goalReason,plan:a.mind.plan,beliefStock:{...a.mind.beliefStock},facts:[...a.mind.facts.entries()],memory:a.mind.memory.slice()},
        social:{trust:[...a.social.trust.entries()],inbox:a.social.inbox.slice(),reputation:{...a.social.reputation},lastMessage:a.social.lastMessage},runtime:{providerSessionId:a.runtime.providerSessionId,providerStatus:a.runtime.providerStatus,lastProvider:a.runtime.lastProvider,lastObservationContract:a.runtime.lastObservationContract,lastDecisionRequest:a.runtime.lastDecisionRequest,lastDecisionResponse:a.runtime.lastDecisionResponse,lastValidation:a.runtime.lastValidation,lastActionType:a.runtime.lastActionType,lastOutcome:a.runtime.lastOutcome,trace:a.runtime.trace.slice()}
      })),
      events:this.events.items.slice()
    };
  }
}

let runtime=new WorldRuntime($("seedInput").value);

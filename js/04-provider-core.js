class DecisionRequestFactory{
  schema(){
    return {
      "$schema":"https://json-schema.org/draft/2020-12/schema","$id":PROTOCOL.decisionRequest,type:"object",additionalProperties:false,
      required:["protocol","requestId","sessionId","simulation","agent","observation","memory","actionContract"],
      properties:{
        protocol:{const:PROTOCOL.decisionRequest},requestId:{type:"string"},sessionId:{type:"string"},
        simulation:{type:"object",required:["id","seed","tick","day","alive","providerHint"]},
        agent:{type:"object",required:["id","name","role","capacity","capabilities"]},
        observation:{"$ref":PROTOCOL.observation},memory:{type:"object"},actionContract:{type:"object"}
      }
    };
  }
  build(state,agent,observation,providerHint){
    const symbolicFacts=[...agent.mind.facts.values()].sort((a,b)=>b.confidence-a.confidence||b.lastSeenTick-a.lastSeenTick)
      .slice(0,CONFIG.maxRequestFacts).map(f=>({key:f.key,value:cloneJson(f.value),confidence:round1(f.confidence),lastSeenTick:f.lastSeenTick,source:f.source}));
    const recentEpisodes=agent.mind.memory.slice(-CONFIG.maxRequestMemories).map(m=>({...m}));
    const allowedTypes=[ACTION.MOVE,ACTION.GATHER,ACTION.DEPOSIT,ACTION.CONSUME,ACTION.REST,ACTION.SHARE,ACTION.WAIT];
    if(agent.role==="builder")allowedTypes.push(ACTION.BUILD);
    if(agent.role==="healer")allowedTypes.push(ACTION.HEAL);
    const request={
      protocol:PROTOCOL.decisionRequest,
      requestId:`${state.simulationId}:${state.tick}:${agent.id}`,
      sessionId:agent.runtime.providerSessionId,
      simulation:{id:state.simulationId,seed:state.seed,tick:state.tick,day:state.day,alive:state.agents.filter(a=>a.alive).length,providerHint},
      agent:{
        id:agent.id,name:agent.name,role:agent.role,capacity:agent.capacity,
        capabilities:{canBuild:agent.role==="builder",canHeal:agent.role==="healer",canScout:agent.role==="scout",canCarry:agent.role==="carrier"}
      },
      observation:cloneJson(observation),
      memory:{
        currentGoal:agent.mind.goal,goalReason:agent.mind.goalReason,currentPlan:agent.mind.plan,
        beliefStock:{...agent.mind.beliefStock},knownShelters:agent.mind.knownShelters,failedActions:agent.mind.failedActions,
        newFactKeys:agent.mind.newFactKeys.slice(0,8),symbolicFacts,recentEpisodes,
        social:{reputation:{...agent.social.reputation},trustedPeers:[...agent.social.trust.entries()].sort((a,b)=>b[1]-a[1]).slice(0,8)}
      },
      actionContract:{
        protocol:PROTOCOL.action,allowedTypes,
        worldBounds:{minX:4,maxX:SPACE.width-4,minY:4,maxY:SPACE.height-4},
        limits:{interactionRange:CONFIG.interactRange,campSyncRange:CONFIG.campSyncRange,communicationRange:CONFIG.communicationRange,maxShareFacts:5,socialIntents:SOCIAL_INTENTS},
        rule:"Return one action only. The provider cannot mutate world state. Every action is validated and resolved by the server-authoritative World Runtime."
      }
    };
    return deepFreeze(request);
  }
}

function makeDecisionResponse(request,providerId,action,cognition={},confidence=.72,replanAfterTicks=24,diagnostics={}){
  return {
    protocol:PROTOCOL.decisionResponse,requestId:request.requestId,agentId:request.agent.id,tick:request.simulation.tick,provider:providerId,
    decision:{
      action:{protocol:PROTOCOL.action,type:action.type,payload:cloneJson(action.payload||{})},
      cognition:{goal:String(cognition.goal||request.memory.currentGoal||"orient"),reason:String(cognition.reason||action.reason||""),plan:String(cognition.plan||action.reason||action.type)},
      reason:String(action.reason||cognition.reason||""),confidence:clamp(Number(confidence)||.5,0,1),replanAfterTicks:clamp(Math.floor(Number(replanAfterTicks)||24),1,120)
    },
    diagnostics:cloneJson(diagnostics||{})
  };
}

class ProviderRegistry{
  constructor(){this.providers=new Map()}
  register(id,adapter,meta={}){
    const key=String(id||"").trim();
    if(!/^[a-z0-9][a-z0-9._-]{1,48}$/i.test(key))throw new Error("Provider id must use 2-49 letters, digits, dot, underscore, or dash");
    if(!adapter||typeof adapter.decide!=="function")throw new Error("Provider adapter must implement decide(request, context)");
    const entry={id:key,adapter,meta:{label:meta.label||key,kind:meta.kind||"custom",async:!!meta.async,description:meta.description||""}};
    this.providers.set(key,entry);return entry;
  }
  get(id){return this.providers.get(id)||null}
  list(){return [...this.providers.values()].map(e=>({id:e.id,...e.meta}))}
}

class LocalPlannerProvider{
  constructor(planner){this.planner=planner;this.id="local"}
  decide(request,context){
    const tempQueue=new ActionQueue();
    context.planner.decide(context.agent,context.observation,tempQueue,context.summary);
    const generated=tempQueue.drain()[0]||{type:ACTION.WAIT,payload:{},reason:"local planner produced no action"};
    const a=context.agent;
    return makeDecisionResponse(request,this.id,generated,{goal:a.mind.goal,reason:a.mind.goalReason,plan:a.mind.plan},.78,Math.max(1,a.mind.replanAtTick-request.simulation.tick),{engine:"deterministic-js-planner"});
  }
}

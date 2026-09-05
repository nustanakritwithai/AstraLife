"use strict";

class AgentStateBoundaryV051{
  static persistent(agent){
    const skills=agent.development?.skills||{};
    return deepFreeze({
      protocol:ASTRA_CORE_PROTOCOLS_V051.agentState,
      agentId:agent.id,
      identity:{id:agent.id,name:agent.name,baseRole:agent.role},
      skills:Object.fromEntries(Object.entries(skills).map(([k,v])=>[k,{xp:Number(v.xp)||0,competency:Number(v.competency)||0,success:Number(v.success)||0,failure:Number(v.failure)||0}])),
      experience:Object.fromEntries(Object.entries(skills).map(([k,v])=>[k,Number(v.xp)||0])),
      competency:Object.fromEntries(Object.entries(skills).map(([k,v])=>[k,Number(v.competency)||0])),
      preferences:{...(agent.development?.preferences||{})},
      domainReputation:{...(agent.development?.domainReputation||{})},
      memory:(agent.mind?.memory||[]).map(m=>cloneJson(m)),
      beliefs:[...(agent.mind?.facts||new Map()).entries()].map(([key,value])=>[key,cloneJson(value)]),
      socialTrust:[...(agent.social?.trust||new Map()).entries()],
      relationships:cloneJson(agent.social?.relationships||{}),
      emergentRole:agent.emergentRole||"generalist",
      providerSession:{sessionId:agent.runtime?.providerSessionId||"",lastProvider:agent.runtime?.lastProvider||"local"}
    });
  }
  static runtime(agent){
    return {
      currentObservation:agent.runtime?.lastObservation||null,
      currentAction:agent.runtime?.lastActionType||null,
      pendingRequest:agent.runtime?.providerStatus==="pending"?agent.runtime?.lastDecisionRequest||null:null,
      currentTarget:agent.mind?.target?cloneJson(agent.mind.target):null,
      runtimeTrace:(agent.runtime?.trace||[]).slice(),
      renderPositionCache:null
    };
  }
  static attach(agent){
    if(!Object.getOwnPropertyDescriptor(agent,"persistentState"))Object.defineProperty(agent,"persistentState",{enumerable:false,configurable:false,get:()=>AgentStateBoundaryV051.persistent(agent)});
    if(!Object.getOwnPropertyDescriptor(agent,"temporaryState"))Object.defineProperty(agent,"temporaryState",{enumerable:false,configurable:false,get:()=>AgentStateBoundaryV051.runtime(agent)});
    return agent;
  }
  static validateSessionIsolation(agents){
    const sessions=agents.map(a=>a.runtime?.providerSessionId).filter(Boolean);
    return {ok:new Set(sessions).size===sessions.length,count:sessions.length,unique:new Set(sessions).size};
  }
}

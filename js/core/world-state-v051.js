"use strict";

class WorldStateBoundaryV051{
  constructor(runtime){this.runtime=runtime;this.gameplayMutationDepth=0;this.outsideResolverMutations=0;this.unvalidatedResolverActions=0}
  attach(){
    const s=this.runtime.state;
    s.worldEvents=this.runtime.events.items;
    s.actionQueue=this.runtime.queue.items;
    s.structures=s.structures||[];
    s.weather=s.weather||{};
    Object.defineProperty(s.weather,"stormTicks",{enumerable:true,configurable:true,get:()=>s.stormTicks,set:v=>{s.stormTicks=v}});
    return s;
  }
  enterResolver(){this.gameplayMutationDepth++}
  exitResolver(){this.gameplayMutationDepth=Math.max(0,this.gameplayMutationDepth-1)}
  recordUnvalidated(){this.unvalidatedResolverActions++}
  runtimeSnapshot(){
    const s=this.runtime.state;
    return deepFreeze({
      protocol:ASTRA_CORE_PROTOCOLS_V051.worldSnapshot,
      simulationId:s.simulationId,seed:s.seed,tick:s.tick,time:s.time,
      weather:{stormTicks:s.stormTicks,active:s.stormTicks>0},
      resources:s.resources.map(r=>cloneJson(r)),
      camp:cloneJson(s.camp),structures:cloneJson(s.structures||[]),
      agents:s.agents.map(a=>({agentId:a.id,alive:a.alive,body:cloneJson(a.body),inventory:cloneJson(a.inventory),emergentRole:a.emergentRole||a.role})),
      worldEvents:this.runtime.events.recent(120).map(e=>cloneJson(e)),
      actionQueue:this.runtime.queue.items.map(a=>cloneJson(a))
    });
  }
  integrity(){return {outsideResolverMutations:this.outsideResolverMutations,unvalidatedResolverActions:this.unvalidatedResolverActions}}
}

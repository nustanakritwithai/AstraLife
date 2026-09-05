"use strict";

const ASTRA_CORE_PROTOCOLS_V051 = Object.freeze({
  observation:"astra.observation.v1",
  decision:"astra.decision.v1",
  action:"astra.action.v1",
  communication:"astra.communication.v1",
  agentState:"astra.agent-state.v1",
  worldSnapshot:"astra.world-snapshot.v1"
});

const ASTRA_FORBIDDEN_MUTATION_ACTIONS = Object.freeze([
  "SET_WORLD_STATE","TELEPORT","SET_HP","ADD_RESOURCE","REMOVE_RESOURCE","SET_RESOURCE","MUTATE_WORLD"
]);

class CoreContractsV051{
  constructor(){this.protocols=ASTRA_CORE_PROTOCOLS_V051}
  observationSchema(){return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":this.protocols.observation,type:"object",additionalProperties:false,required:["protocol","observationId","agentId","tick","self","visibleEntities","visibleResources","nearbyAgents","messages","environment"],properties:{protocol:{const:this.protocols.observation},observationId:{type:"string"},agentId:{type:"integer",minimum:1},tick:{type:"integer",minimum:0},self:{type:"object"},visibleEntities:{type:"array"},visibleResources:{type:"array"},nearbyAgents:{type:"array"},messages:{type:"array"},environment:{type:"object"}},rule:"Immutable, visibility-filtered snapshot. Never expose the whole WorldState."}}
  decisionSchema(){return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":this.protocols.decision,type:"object",additionalProperties:false,required:["protocol","decisionId","agentId","sessionId","observationId","tick","action"],properties:{protocol:{const:this.protocols.decision},decisionId:{type:"string"},agentId:{type:"integer",minimum:1},sessionId:{type:"string"},observationId:{type:"string"},tick:{type:"integer",minimum:0},goal:{type:"string"},action:{type:"object",required:["type","payload"]},confidence:{type:"number",minimum:0,maximum:1}},rule:"Provider proposes only. Provider cannot mutate WorldState."}}
  actionSchema(){return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":this.protocols.action,type:"object",required:["protocol","decisionId","agentId","tick","type","payload","validated"],properties:{protocol:{const:this.protocols.action},decisionId:{type:"string"},agentId:{type:"integer",minimum:1},tick:{type:"integer",minimum:0},type:{type:"string",not:{enum:ASTRA_FORBIDDEN_MUTATION_ACTIONS}},payload:{type:"object"},validated:{const:true}},rule:"Only validated actions may enter the ActionQueue."}}
  communicationSchema(){return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":this.protocols.communication,type:"object",required:["protocol","from","to","tick","intent","facts"],properties:{protocol:{const:this.protocols.communication},from:{type:"integer"},to:{type:"integer"},tick:{type:"integer"},intent:{type:"string"},facts:{type:"array"}}}}
  agentStateSchema(){return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":this.protocols.agentState,type:"object",required:["protocol","agentId","identity","skills","experience","competency","preferences","domainReputation","memory","beliefs","socialTrust","relationships","emergentRole","providerSession"],properties:{protocol:{const:this.protocols.agentState},agentId:{type:"integer",minimum:1},identity:{type:"object"},skills:{type:"object"},experience:{type:"object"},competency:{type:"object"},preferences:{type:"object"},domainReputation:{type:"object"},memory:{type:"array"},beliefs:{type:"array"},socialTrust:{type:"array"},relationships:{type:"object"},emergentRole:{type:"string"},providerSession:{type:"object"}},rule:"Persistent identity/state only. Temporary observation/action/trace/render caches are excluded."}}
  worldSnapshotSchema(){return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":this.protocols.worldSnapshot,type:"object",required:["protocol","simulationId","seed","tick","time","weather","resources","camp","structures","agents","worldEvents","actionQueue"],properties:{protocol:{const:this.protocols.worldSnapshot},simulationId:{type:"string"},seed:{type:"string"},tick:{type:"integer"},time:{type:"number"},weather:{type:"object"},resources:{type:"array"},camp:{type:"object"},structures:{type:"array"},agents:{type:"array"},worldEvents:{type:"array"},actionQueue:{type:"array"}},rule:"Read-only runtime snapshot derived from WorldState."}}
  bundle(){return Object.freeze({version:"0.5.1",protocols:this.protocols,schemas:{observation:this.observationSchema(),decision:this.decisionSchema(),action:this.actionSchema(),communication:this.communicationSchema(),agentState:this.agentStateSchema(),worldSnapshot:this.worldSnapshotSchema()},authority:Object.freeze({provider:"PROPOSE",validator:"ACCEPT_OR_REJECT",resolver:"MUTATE_WORLDSTATE"}),forbiddenMutationActions:ASTRA_FORBIDDEN_MUTATION_ACTIONS.slice()})}
}

class EnvironmentSystem{
  constructor(events){this.events=events}
  update(state){
    state.time+=1;state.day=1+Math.floor(state.tick/CONFIG.dayTicks);
    if(state.stormTicks>0)state.stormTicks--;
    for(const r of state.resources){
      const regen=CONFIG.resourceRegen[r.type]||0;
      if(regen>0)r.amount=Math.min(r.max,r.amount+regen);
    }
    for(const agent of state.agents)this.physiology(state,agent);
  }
  physiology(state,a){
    if(!a.alive)return;
    a.body.ageTicks++;
    a.body.hunger=clamp(a.body.hunger+.0072*(state.stormTicks>0?1.18:1),0,110);
    a.body.thirst=clamp(a.body.thirst+.0112*(state.stormTicks>0?1.12:1),0,110);
    if(a.runtime.lastActionType!==ACTION.REST)a.body.energy=clamp(a.body.energy-.0027,0,100);
    let damage=0;
    if(a.body.hunger>95)damage+=(a.body.hunger-94)*.0035;
    if(a.body.thirst>92)damage+=(a.body.thirst-91)*.0055;
    if(a.body.energy<3)damage+=.016;
    if(state.stormTicks>0&&distance(a.body,state.camp)>state.camp.r+25)damage+=.024;
    const phase=(state.tick%CONFIG.dayTicks)/CONFIG.dayTicks;
    if(phase>.68&&state.camp.shelter===0&&distance(a.body,state.camp)>72)damage+=.006;
    a.body.hp-=damage;
    if(a.body.hp<=0){
      a.body.hp=0;a.alive=false;state.metrics.deaths++;
      this.events.emit(state.tick,"DEATH",`${a.name} เสียชีวิต ขณะทำเป้าหมาย ${a.mind.goal}`,{agentId:a.id,goal:a.mind.goal},"danger");
    }
  }
}

function socialCommunicationSchema(){
  return {
    "$schema":"https://json-schema.org/draft/2020-12/schema","$id":PROTOCOL.communication,type:"object",additionalProperties:false,
    required:["protocol","id","from","to","intent","tick","urgency","text","replyTo","facts"],
    properties:{
      protocol:{const:PROTOCOL.communication},id:{type:"integer",minimum:1},from:{type:"integer",minimum:1},to:{type:"integer",minimum:1},
      intent:{enum:SOCIAL_INTENTS},tick:{type:"integer",minimum:0},urgency:{type:"number",minimum:0,maximum:1},text:{type:"string",maxLength:180},
      replyTo:{anyOf:[{type:"integer",minimum:1},{type:"null"}]},facts:{type:"array",maxItems:5}
    }
  };
}

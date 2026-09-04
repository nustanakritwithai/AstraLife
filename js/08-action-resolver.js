class ActionResolver{
  constructor(memory,events){this.memory=memory;this.events=events}
  outcome(action,ok,message,significant=false,extra={}){
    return Object.freeze({actionId:action.id,agentId:action.agentId,actionType:action.type,ok,message,significant,...extra});
  }
  resolve(state,actions){
    const outcomes=[],permitted=[];
    for(const action of actions){
      if(!action.meta||action.meta.validated!==true)outcomes.push(this.outcome(action,false,"unvalidated action blocked by resolver gate",true));
      else permitted.push(action);
    }
    const buildActions=permitted.filter(a=>a.type===ACTION.BUILD);
    const regular=permitted.filter(a=>a.type!==ACTION.BUILD);
    for(const action of regular){
      const agent=state.agentById.get(action.agentId);
      if(!agent||!agent.alive){outcomes.push(this.outcome(action,false,"actor unavailable"));continue}
      switch(action.type){
        case ACTION.MOVE:outcomes.push(this.resolveMove(state,agent,action));break;
        case ACTION.GATHER:outcomes.push(this.resolveGather(state,agent,action));break;
        case ACTION.DEPOSIT:outcomes.push(this.resolveDeposit(state,agent,action));break;
        case ACTION.CONSUME:outcomes.push(this.resolveConsume(state,agent,action));break;
        case ACTION.REST:outcomes.push(this.resolveRest(state,agent,action));break;
        case ACTION.HEAL:outcomes.push(this.resolveHeal(state,agent,action));break;
        case ACTION.SHARE:outcomes.push(this.resolveShare(state,agent,action));break;
        case ACTION.WAIT:outcomes.push(this.outcome(action,true,action.reason||"wait"));break;
        default:outcomes.push(this.outcome(action,false,"unsupported action"));
      }
    }
    outcomes.push(...this.resolveBuildBatch(state,buildActions));
    return outcomes;
  }
  resolveMove(state,agent,action){
    const target={x:clamp(Number(action.payload.x)||agent.body.x,5,SPACE.width-5),y:clamp(Number(action.payload.y)||agent.body.y,5,SPACE.height-5)};
    const dx=target.x-agent.body.x,dy=target.y-agent.body.y,d=Math.hypot(dx,dy)||1;
    if(d<5)return this.outcome(action,true,"target reached",false,{reached:true});
    const fatigue=clamp(agent.body.energy/38,.42,1);
    const weather=state.stormTicks>0?.63:1;
    const speed=clamp(Number(action.payload.speed)||1,.35,1.35);
    const step=Math.min(d,3.0*fatigue*weather*speed);
    agent.body.x=clamp(agent.body.x+dx/d*step,4,SPACE.width-4);
    agent.body.y=clamp(agent.body.y+dy/d*step,4,SPACE.height-4);
    agent.body.energy=clamp(agent.body.energy-.014*step,0,100);
    return this.outcome(action,true,`moved ${round1(step)} units`,false,{reached:d-step<5});
  }
  resolveGather(state,agent,action){
    const r=state.resourceById.get(action.payload.resourceId);
    if(!r||r.amount<=.05)return this.outcome(action,false,"resource depleted or unknown",true,{resourceId:action.payload.resourceId,invalidateFact:true});
    if(distance(agent.body,r)>CONFIG.interactRange+2)return this.outcome(action,false,"resource outside interaction range",false,{resourceId:action.payload.resourceId,invalidateFact:true});
    const carryType=action.payload.carryType;
    if(agent.inventory.amount>0&&agent.inventory.type!==carryType)return this.outcome(action,false,"inventory contains another resource",false,{resourceId:r.id});
    const room=agent.capacity-agent.inventory.amount;
    if(room<=.05)return this.outcome(action,false,"inventory full",false,{resourceId:r.id});
    const skill=agent.role==="gatherer"?1.32:agent.role==="carrier"?1.12:1;
    const take=Math.min(room,r.amount,.42*skill);
    r.amount-=take;agent.inventory.type=carryType;agent.inventory.amount+=take;
    state.metrics.actionCounts.GATHER++;
    const full=agent.inventory.amount>=agent.capacity-.05;
    return this.outcome(action,true,`gathered ${round1(take)} ${carryType}`,full,{amount:take,resourceId:r.id});
  }
  resolveDeposit(state,agent,action){
    if(distance(agent.body,state.camp)>CONFIG.campSyncRange)return this.outcome(action,false,"not inside camp deposit range");
    if(!agent.inventory.type||agent.inventory.amount<=.01)return this.outcome(action,false,"inventory empty");
    const type=agent.inventory.type,amount=agent.inventory.amount;
    state.stock[type]=(state.stock[type]||0)+amount;
    agent.inventory={type:null,amount:0};
    agent.mind.beliefStock={...state.stock};agent.mind.replanAtTick=state.tick;
    state.metrics.cooperativeActions++;state.metrics.actionCounts.DEPOSIT++;
    if(state.tick-state.metrics.lastDepositEventTick>18){
      this.events.emit(state.tick,"DEPOSIT",`${agent.name} ส่ง ${round1(amount)} ${type} เข้าคลังส่วนกลาง`,{agentId:agent.id,type,amount});
      state.metrics.lastDepositEventTick=state.tick;
    }
    return this.outcome(action,true,`deposited ${round1(amount)} ${type} to communal stock`,true,{amount,type});
  }
  resolveConsume(state,agent,action){
    const type=action.payload.resource;
    const inventoryType=type==="water"?"water":"food";
    let source="";
    if(agent.inventory.type===inventoryType&&agent.inventory.amount>=1){
      agent.inventory.amount-=1;if(agent.inventory.amount<.01)agent.inventory={type:null,amount:0};source="carried supply";
    }else if(distance(agent.body,state.camp)<=CONFIG.campSyncRange&&state.stock[inventoryType]>=1){
      state.stock[inventoryType]-=1;source="communal stock";
    }else return this.outcome(action,false,`no reachable ${inventoryType}`);
    if(type==="water")agent.body.thirst=clamp(agent.body.thirst-68,0,110);
    else agent.body.hunger=clamp(agent.body.hunger-64,0,110);
    agent.mind.replanAtTick=state.tick;
    return this.outcome(action,true,`consumed ${inventoryType} from ${source}`,true);
  }
  resolveRest(state,agent,action){
    const atCamp=distance(agent.body,state.camp)<=CONFIG.campSyncRange;
    const shelterBonus=atCamp?Math.min(state.camp.shelter*.09,.55):0;
    agent.body.energy=clamp(agent.body.energy+(atCamp?.48:.18)+shelterBonus,0,100);
    if(agent.body.energy>76)agent.mind.replanAtTick=state.tick;
    return this.outcome(action,true,`rested${atCamp?" at camp":" in the wild"}`);
  }
  resolveHeal(state,agent,action){
    const target=state.agentById.get(action.payload.targetAgentId);
    if(!target||!target.alive)return this.outcome(action,false,"patient unavailable");
    if(distance(agent.body,target.body)>CONFIG.interactRange+5)return this.outcome(action,false,"patient out of range");
    let heal=agent.role==="healer"?1.45:.45;
    if(distance(agent.body,state.camp)<=90&&state.stock.medicine>=.025){state.stock.medicine-=.025;heal*=1.35}
    const before=target.body.hp;target.body.hp=clamp(target.body.hp+heal,0,100);
    state.metrics.cooperativeActions++;state.metrics.actionCounts.HEAL++;
    const oldTrust=target.social.trust.get(agent.id)??.55;target.social.trust.set(agent.id,clamp(oldTrust+.006,.05,.98));
    return this.outcome(action,true,`treated ${target.name} +${round1(target.body.hp-before)} HP`,false,{targetAgentId:target.id});
  }
  resolveShare(state,agent,action){
    const p=action.payload||{},facts=(p.facts||[]).slice(0,5).filter(f=>f&&f.key);
    if(["REPORT","SYNC"].includes(p.intent)&&!facts.length)return this.outcome(action,false,"report has no factual claims");
    let recipients=[];
    if(p.targetAgentId){const target=state.agentById.get(p.targetAgentId);if(target&&target.alive&&target.id!==agent.id&&distance(agent.body,target.body)<=CONFIG.communicationRange)recipients=[target]}
    else recipients=state.agents.filter(b=>b.alive&&b.id!==agent.id&&distance(agent.body,b.body)<=CONFIG.communicationRange).sort((a,b)=>distance(agent.body,a.body)-distance(agent.body,b.body)).slice(0,8);
    if(!recipients.length)return this.outcome(action,false,"no intended peer in communication range");
    const packetFacts=facts.map(f=>Object.freeze({key:f.key,value:{...f.value},confidence:clamp(f.confidence,0,1)}));
    const messageId=state.nextMessageId++;
    for(const receiver of recipients){
      const packet=Object.freeze({protocol:PROTOCOL.communication,id:messageId,from:agent.id,to:receiver.id,intent:p.intent||"SYNC",tick:state.tick,urgency:clamp(p.urgency??.45,0,1),text:String(p.text||"").slice(0,180),replyTo:p.replyTo||null,facts:packetFacts});
      receiver.social.inbox.push(packet);if(receiver.social.inbox.length>CONFIG.maxSocialInbox)receiver.social.inbox.shift();
      state.effects.messages.push({fromId:agent.id,toId:receiver.id,bornTick:state.tick,intent:packet.intent});
    }
    const r=agent.social.reputation;r.messagesSent+=recipients.length;if(p.intent==="REPORT")r.reports++;if(p.intent==="REQUEST_HELP")r.helpRequests++;if(p.intent==="OFFER")r.offers++;if(p.intent==="WARN")r.warnings++;
    state.metrics.socialMessages+=recipients.length;state.metrics.intentCounts[p.intent]=(state.metrics.intentCounts[p.intent]||0)+recipients.length;state.metrics.cooperativeActions++;state.metrics.actionCounts.SHARE++;
    return this.outcome(action,true,`${p.intent} #${messageId} → ${recipients.length} peer(s)${packetFacts.length?` · ${packetFacts.length} claim(s)`:""}`,true,{messageId,recipients:recipients.map(r=>r.id)});
  }
  resolveBuildBatch(state,actions){
    if(!actions.length)return [];
    const outcomes=[];
    const valid=actions.map(a=>({action:a,agent:state.agentById.get(a.agentId)}))
      .filter(x=>x.agent&&x.agent.alive&&x.agent.role==="builder"&&distance(x.agent.body,state.camp)<=45);
    const invalidIds=new Set(actions.map(a=>a.id));for(const x of valid)invalidIds.delete(x.action.id);
    for(const a of actions)if(invalidIds.has(a.id))outcomes.push(this.outcome(a,false,"builder unavailable or outside construction zone"));
    if(valid.length<2){for(const x of valid)outcomes.push(this.outcome(x.action,false,"construction requires at least two builders"));return outcomes}

    const c=state.camp.construction;
    if(!c.active){
      if(state.stock.wood<CONFIG.buildWoodCost){for(const x of valid)outcomes.push(this.outcome(x.action,false,"communal wood below project cost"));return outcomes}
      state.stock.wood-=CONFIG.buildWoodCost;c.active=true;c.progress=0;c.startedTick=state.tick;
      this.events.emit(state.tick,"BUILD_START",`ทีม Builder ${valid.length} คนเริ่มโครงการที่พักใหม่`,{crew:valid.map(x=>x.agent.id)},"important");
    }
    const contribution=valid.reduce((sum,x)=>sum+(x.agent.role==="builder"?1.25:1),0);
    c.progress+=contribution;c.crew=valid.map(x=>x.agent.id);
    state.metrics.cooperativeActions+=valid.length;state.metrics.actionCounts.BUILD+=valid.length;
    for(const x of valid)outcomes.push(this.outcome(x.action,true,`construction +${round1(contribution)} team progress`,false,{progress:c.progress}));
    if(c.progress>=CONFIG.buildRequiredProgress){
      state.camp.shelter++;c.active=false;c.progress=0;c.crew=[];state.metrics.structures++;
      this.events.emit(state.tick,"BUILD_COMPLETE",`สร้างที่พักหลังที่ ${state.camp.shelter} สำเร็จด้วยแรงงานร่วมกัน`,{shelter:state.camp.shelter},"important");
      for(const x of valid){x.agent.mind.replanAtTick=state.tick;this.memory.remember(x.agent,`completed communal shelter #${state.camp.shelter}`,"success")}
    }
    return outcomes;
  }
}

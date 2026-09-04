class ActionContractValidator{
  actionSchema(){
    return {
      "$schema":"https://json-schema.org/draft/2020-12/schema","$id":PROTOCOL.action,type:"object",additionalProperties:false,
      required:["protocol","type","payload"],properties:{protocol:{const:PROTOCOL.action},type:{enum:Object.values(ACTION)},payload:{type:"object"}},
      payloadRules:{
        MOVE:{required:["x","y"],optional:["speed"]},GATHER:{required:["resourceId","resourceType","carryType"]},
        DEPOSIT:{required:[]},CONSUME:{required:["resource"]},REST:{required:[]},BUILD:{required:[]},HEAL:{required:["targetAgentId"]},
        SHARE:{required:["intent","facts"],optional:["targetAgentId","replyTo","urgency","text"],limits:{facts:5,intents:SOCIAL_INTENTS}},WAIT:{required:[]}
      }
    };
  }
  responseSchema(){
    return {
      "$schema":"https://json-schema.org/draft/2020-12/schema","$id":PROTOCOL.decisionResponse,type:"object",additionalProperties:true,
      required:["protocol","requestId","agentId","tick","provider","decision"],
      properties:{
        protocol:{const:PROTOCOL.decisionResponse},requestId:{type:"string"},agentId:{type:"integer"},tick:{type:"integer"},provider:{type:"string"},
        decision:{type:"object",required:["action","cognition","reason","confidence","replanAfterTicks"],properties:{action:{"$ref":PROTOCOL.action},confidence:{type:"number",minimum:0,maximum:1},replanAfterTicks:{type:"integer",minimum:1,maximum:120}}}
      }
    };
  }
  validate(response,request,state){
    const errors=[];const need=(ok,msg)=>{if(!ok)errors.push(msg)};
    let raw=response;
    try{
      const encoded=JSON.stringify(response);need(encoded.length<=CONFIG.maxRemoteResponseBytes,"response exceeds size limit");raw=JSON.parse(encoded);
    }catch(error){return {ok:false,errors:[`response is not JSON-serializable: ${error.message}`]}}
    need(isPlainObject(raw),"response must be a plain object");
    if(!isPlainObject(raw))return {ok:false,errors};
    need(raw.protocol===PROTOCOL.decisionResponse,"decision response protocol mismatch");
    need(raw.requestId===request.requestId,"requestId mismatch");
    need(raw.agentId===request.agent.id,"agentId mismatch");
    need(raw.tick===request.simulation.tick,"decision tick mismatch");
    need(typeof raw.provider==="string"&&raw.provider.length>=2&&raw.provider.length<=64,"provider id invalid");
    const expectedProvider=request.simulation.providerHint==="local-fallback"?"local":request.simulation.providerHint;
    need(raw.provider===expectedProvider,`provider mismatch: expected ${expectedProvider}`);
    need(state.tick-request.simulation.tick<=CONFIG.maxDecisionAge,"decision is too stale");
    need(isPlainObject(raw.decision),"decision object missing");
    if(!isPlainObject(raw.decision))return {ok:false,errors};
    const d=raw.decision,a=d.action;
    need(isPlainObject(a),"decision.action missing");
    if(!isPlainObject(a))return {ok:false,errors};
    need(a.protocol===PROTOCOL.action,"action protocol mismatch");
    need(request.actionContract.allowedTypes.includes(a.type),`action ${a.type} is not allowed for this agent`);
    need(isPlainObject(a.payload),"action.payload must be an object");
    const payload=isPlainObject(a.payload)?a.payload:{};let sanitized={};

    switch(a.type){
      case ACTION.MOVE:{
        need(finite(payload.x)&&finite(payload.y),"MOVE requires finite x and y");
        const x=Number(payload.x),y=Number(payload.y),speed=payload.speed==null?1:Number(payload.speed);
        need(x>=4&&x<=SPACE.width-4&&y>=4&&y<=SPACE.height-4,"MOVE target outside world bounds");
        need(finite(speed)&&speed>=.35&&speed<=1.35,"MOVE speed outside 0.35..1.35");sanitized={x,y,speed};break;
      }
      case ACTION.GATHER:{
        need(Number.isInteger(payload.resourceId)&&payload.resourceId>0,"GATHER resourceId invalid");
        need(RESOURCE_TYPES.includes(payload.resourceType),"GATHER resourceType invalid");
        need(CARRY_TYPES.includes(payload.carryType),"GATHER carryType invalid");
        const mapping={water:"water",berry:"food",tree:"wood",herb:"medicine"};need(mapping[payload.resourceType]===payload.carryType,"GATHER resource/carry mapping invalid");
        sanitized={resourceId:payload.resourceId,resourceType:payload.resourceType,carryType:payload.carryType};break;
      }
      case ACTION.CONSUME:need(["water","food"].includes(payload.resource),"CONSUME resource invalid");sanitized={resource:payload.resource};break;
      case ACTION.HEAL:need(Number.isInteger(payload.targetAgentId)&&payload.targetAgentId>0,"HEAL targetAgentId invalid");sanitized={targetAgentId:payload.targetAgentId};break;
      case ACTION.SHARE:{
        need(SOCIAL_INTENTS.includes(payload.intent),"SHARE intent invalid");
        need(payload.targetAgentId==null||(Number.isInteger(payload.targetAgentId)&&payload.targetAgentId>0),"SHARE targetAgentId invalid");
        need(payload.replyTo==null||(Number.isInteger(payload.replyTo)&&payload.replyTo>0),"SHARE replyTo invalid");
        need(payload.urgency==null||(finite(payload.urgency)&&Number(payload.urgency)>=0&&Number(payload.urgency)<=1),"SHARE urgency invalid");
        need(payload.text==null||(typeof payload.text==="string"&&payload.text.length<=180),"SHARE text invalid");
        need(Array.isArray(payload.facts)&&payload.facts.length<=5,"SHARE facts must contain 0..5 items");
        if(["REPORT","SYNC"].includes(payload.intent))need(Array.isArray(payload.facts)&&payload.facts.length>0,"REPORT/SYNC requires facts");
        const facts=[];
        if(Array.isArray(payload.facts))for(const [index,f] of payload.facts.slice(0,5).entries()){
          need(isPlainObject(f),`SHARE facts[${index}] invalid`);if(!isPlainObject(f))continue;
          need(typeof f.key==="string"&&f.key.length>0&&f.key.length<=100,`SHARE facts[${index}].key invalid`);
          need(isPlainObject(f.value),`SHARE facts[${index}].value invalid`);
          need(finite(f.confidence)&&Number(f.confidence)>=0&&Number(f.confidence)<=1,`SHARE facts[${index}].confidence invalid`);
          let value={};try{value=cloneJson(f.value);need(JSON.stringify(value).length<=4096,`SHARE facts[${index}].value too large`)}catch(error){need(false,`SHARE facts[${index}].value not serializable`)}
          facts.push({key:String(f.key||"").slice(0,100),value,confidence:clamp(Number(f.confidence)||0,0,1)});
        }
        sanitized={intent:String(payload.intent||"SYNC").slice(0,24),targetAgentId:payload.targetAgentId||null,replyTo:payload.replyTo||null,urgency:clamp(Number(payload.urgency??.45),0,1),text:String(payload.text||"").slice(0,180),facts};break;
      }
      case ACTION.DEPOSIT:case ACTION.REST:case ACTION.BUILD:case ACTION.WAIT:sanitized={};break;
      default:need(false,`unsupported action type ${a.type}`);
    }
    need(typeof d.reason==="string"&&d.reason.length<=240,"decision.reason invalid");
    need(finite(d.confidence)&&Number(d.confidence)>=0&&Number(d.confidence)<=1,"decision.confidence invalid");
    need(Number.isInteger(d.replanAfterTicks)&&d.replanAfterTicks>=1&&d.replanAfterTicks<=120,"decision.replanAfterTicks invalid");
    need(isPlainObject(d.cognition),"decision.cognition invalid");
    const cognition=isPlainObject(d.cognition)?{
      goal:String(d.cognition.goal||"").slice(0,80),reason:String(d.cognition.reason||"").slice(0,180),plan:String(d.cognition.plan||"").slice(0,220)
    }:{goal:"",reason:"",plan:""};
    need(cognition.goal.length>0,"cognition.goal missing");
    if(errors.length)return {ok:false,errors:errors.slice(0,24)};
    return {ok:true,errors:[],normalized:{provider:raw.provider,action:{type:a.type,payload:sanitized},cognition,reason:d.reason,confidence:Number(d.confidence),replanAfterTicks:d.replanAfterTicks,sourceTick:request.simulation.tick,requestId:request.requestId,raw}};
  }
}

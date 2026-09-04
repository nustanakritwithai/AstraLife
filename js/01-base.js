"use strict";

const VERSION = "0.4.0";
const SPACE = Object.freeze({ width:1200, height:720 });
const CONFIG = Object.freeze({
  initialAgents:60,
  observationRange:105,
  scoutRange:165,
  communicationRange:205,
  distressRange:95,
  campSyncRange:58,
  interactRange:14,
  maxFacts:90,
  maxMemory:24,
  maxTrace:14,
  dayTicks:420,
  stormDurationTicks:150,
  resourceRegen:{ water:0.018, berry:0.012, tree:0.0012, herb:0.002 },
  buildWoodCost:12,
  buildRequiredProgress:115,
  maxDecisionAge:90,
  providerTimeoutMs:8000,
  maxRemoteResponseBytes:65536,
  maxRequestFacts:26,
  maxRequestMemories:9,
  maxSocialInbox:28,
  socialCooldownMin:18,
  socialCooldownMax:38
});

const ACTION = Object.freeze({
  MOVE:"MOVE", GATHER:"GATHER", DEPOSIT:"DEPOSIT", CONSUME:"CONSUME",
  REST:"REST", BUILD:"BUILD", HEAL:"HEAL", SHARE:"SHARE", WAIT:"WAIT"
});
const PRIORITY = Object.freeze({CONSUME:100,HEAL:90,DEPOSIT:80,GATHER:70,BUILD:60,SHARE:55,MOVE:40,REST:30,WAIT:0});
const ROLE_COLORS = Object.freeze({scout:"#7fdcff",gatherer:"#a9f58c",builder:"#ffd36a",healer:"#ff9cae",carrier:"#c6a4ff"});
const RESOURCE_COLORS = Object.freeze({water:"#4ba5ef",berry:"#dc70f2",tree:"#3f8b54",herb:"#9cf39f"});
const PROTOCOL = Object.freeze({
  observation:"astra-colony.observation.v1",
  decisionRequest:"astra-colony.decision-request.v1",
  decisionResponse:"astra-colony.decision-response.v1",
  action:"astra-colony.action.v1",
  provider:"astra-colony.provider.v1",
  communication:"astra-colony.communication.v1"
});
const PROVIDER_MODE = Object.freeze({LOCAL:"local",ASTRA_SIM:"astra-sim",HYBRID:"hybrid",REMOTE:"remote"});
const SOCIAL_INTENTS = Object.freeze(["ASK","REPORT","REQUEST_HELP","OFFER","WARN","SYNC"]);
const RESOURCE_TYPES = Object.freeze(["water","berry","tree","herb"]);
const CARRY_TYPES = Object.freeze(["water","food","wood","medicine"]);
const PROVIDER_RING = Object.freeze({local:"#77f2ad","astra-sim":"#d393ff",remote:"#75c9ff"});

const $ = id => document.getElementById(id);
const canvas = $("world");
const ctx = canvas.getContext("2d", { alpha:false });
const ui = Object.fromEntries([
  "alive","day","tick","food","water","wood","shelter","knowledge","coop","queued","failures","providerCalls","invalidDecisions","fallbacks","pending","obsErrors","integrity",
  "runtimeMeta","eventLog","inspector","iname","imeta","bhp","bhunger","bthirst","benergy","igoal","iprovider","irequest","iresponse","iobs","iwm","imem","itrace",
  "providerBadge","contractModal","contractView","contractContent","contractStatus","messagesSent","verifiedClaims","avgCredibility","isocial"
].map(id => [id,$(id)]));

let CSS_W=0, CSS_H=0, DPR=1;
function resizeCanvas(){
  const r=canvas.getBoundingClientRect();
  CSS_W=Math.max(1,r.width); CSS_H=Math.max(1,r.height); DPR=Math.min(window.devicePixelRatio||1,2);
  canvas.width=Math.floor(CSS_W*DPR); canvas.height=Math.floor(CSS_H*DPR);
  ctx.setTransform(DPR,0,0,DPR,0,0);
}
addEventListener("resize",resizeCanvas); resizeCanvas();

const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
const round1=n=>Math.round(n*10)/10;
const copyPoint=p=>({x:p.x,y:p.y});
const isPlainObject=value=>!!value&&typeof value==="object"&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype;
const finite=value=>value!==null&&value!==""&&Number.isFinite(Number(value));
function cloneJson(value){return JSON.parse(JSON.stringify(value))}
function deepFreeze(value){
  if(value&&typeof value==="object"&&!Object.isFrozen(value)){
    Object.freeze(value);for(const key of Object.keys(value))deepFreeze(value[key]);
  }
  return value;
}
function clippedJson(value,limit=5200){
  if(value==null)return "-";
  let text;try{text=JSON.stringify(value,null,2)}catch(error){text=`[unserializable: ${error.message}]`}
  return text.length>limit?text.slice(0,limit)+`
… clipped ${text.length-limit} characters`:text;
}

function hashSeed(value){
  const s=String(value||"ASTRA-2026");
  let h=2166136261>>>0;
  for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}
  return h>>>0 || 0x9e3779b9;
}
class SeededRandom{
  constructor(seed){this.seedText=String(seed);this.state=hashSeed(seed)}
  next(){
    let t=this.state+=0x6D2B79F5;
    t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);
    return ((t^t>>>14)>>>0)/4294967296;
  }
  float(min=0,max=1){return min+(max-min)*this.next()}
  int(min,max){return Math.floor(this.float(min,max+1))}
  pick(list){return list[Math.floor(this.next()*list.length)]}
  chance(p){return this.next()<p}
}

class EventStore{
  constructor(limit=700){this.limit=limit;this.items=[];this.nextId=1}
  emit(tick,type,message,meta={},severity="normal"){
    const event=Object.freeze({id:this.nextId++,tick,type,message,meta,severity});
    this.items.push(event);
    if(this.items.length>this.limit)this.items.splice(0,this.items.length-this.limit);
    return event;
  }
  recent(count=20){return this.items.slice(-count)}
}

class ActionQueue{
  constructor(){this.items=[];this.nextId=1}
  enqueue(tick,agentId,type,payload={},reason="",meta={}){
    if(!Object.values(ACTION).includes(type))throw new Error(`Unknown action: ${type}`);
    const action=Object.freeze({id:this.nextId++,tick,agentId,type,payload:deepFreeze(cloneJson(payload||{})),reason,priority:PRIORITY[type]||0,meta:deepFreeze(cloneJson(meta||{}))});
    this.items.push(action);return action;
  }
  drain(){
    const out=this.items.slice().sort((a,b)=>b.priority-a.priority||a.agentId-b.agentId||a.id-b.id);
    this.items.length=0;return out;
  }
}

(() => {
  "use strict";

  const VERSION = "p6.8-adaptive-full-throughput";
  const PROVIDER_ID = "typhoon-byok";
  const LANE_COUNT = 3;
  const MAX_ACTIVE_TOTAL = 48;
  const MIN_ACTIVE_TOTAL = 6;
  const MAX_CALLS_PER_MINUTE = 195;
  const MAX_QUEUE_TOTAL = 96;
  const RECOVER_AFTER_MS = 10000;
  const RECOVER_EVERY_SUCCESSES = 6;

  const existing = runtime.registry.get(PROVIDER_ID);
  if(!existing?.adapter || typeof existing.adapter.decide !== "function")return;
  const original = existing.adapter;
  const baseApi = window.AstraLifeTyphoonBYOK;

  const lanes = Array.from({length:LANE_COUNT},(_,index)=>({
    index,
    name:String.fromCharCode(65+index),
    queue:[],
    active:0,
    started:0,
    completed:0,
    failed:0,
    maxQueue:0
  }));
  const starts = [];
  let timer = null;
  let rrCursor = 0;
  let activeCeiling = MAX_ACTIVE_TOTAL;
  let lastBackoffAt = 0;
  let successesSinceRecoveryStep = 0;

  const stats = {
    enqueued:0,started:0,completed:0,failed:0,
    maxObservedActive:0,maxObservedQueue:0,
    concurrencyBackoffs:0,concurrencyRecoveries:0,
    lastError:null,lastSuccessAt:null,lastBackoffAt:null
  };

  const totalActive=()=>lanes.reduce((sum,w)=>sum+w.active,0);
  const totalQueued=()=>lanes.reduce((sum,w)=>sum+w.queue.length,0);
  const laneCeiling=()=>Math.max(1,Math.ceil(activeCeiling/LANE_COUNT));

  function prune(now=Date.now()){
    const floor=now-60000;
    while(starts.length && starts[0] <= floor)starts.shift();
  }

  function laneIndexFor(request){
    const id=Math.max(1,Number(request?.agent?.id)||1);
    return (id-1)%LANE_COUNT;
  }

  function priorityFor(request){
    const selected=Number(runtime.selectedAgentId);
    const id=Number(request?.agent?.id);
    if(Number.isFinite(selected) && selected===id)return 1000;
    const self=request?.observation?.self||{};
    let score=0;
    if(Number(self.hp)<45)score+=120;
    if(Number(self.thirst)>78)score+=90;
    if(Number(self.hunger)>80)score+=70;
    return score;
  }

  function insertJob(lane,job){
    const p=priorityFor(job.request);
    job.priority=p;
    let i=lane.queue.length;
    while(i>0 && lane.queue[i-1].priority<p)i--;
    lane.queue.splice(i,0,job);
    lane.maxQueue=Math.max(lane.maxQueue,lane.queue.length);
    stats.maxObservedQueue=Math.max(stats.maxObservedQueue,totalQueued());
  }

  function schedulePump(delayMs){
    if(timer)return;
    timer=setTimeout(()=>{timer=null;pump();},Math.max(10,delayMs|0));
  }

  function nextRateDelay(now=Date.now()){
    prune(now);
    if(starts.length<MAX_CALLS_PER_MINUTE)return 0;
    return Math.max(25,60000-(now-starts[0])+10);
  }

  function reduceConcurrency(error){
    const msg=String(error?.message||error||"");
    if(!/429|rate.?limit/i.test(msg))return;
    const next=Math.max(MIN_ACTIVE_TOTAL,Math.floor(activeCeiling*.65));
    if(next<activeCeiling){
      activeCeiling=next;
      lastBackoffAt=Date.now();
      successesSinceRecoveryStep=0;
      stats.concurrencyBackoffs++;
      stats.lastBackoffAt=lastBackoffAt;
    }
  }

  function maybeRecoverConcurrency(){
    if(activeCeiling>=MAX_ACTIVE_TOTAL)return;
    if(Date.now()-lastBackoffAt<RECOVER_AFTER_MS)return;
    successesSinceRecoveryStep++;
    if(successesSinceRecoveryStep<RECOVER_EVERY_SUCCESSES)return;
    successesSinceRecoveryStep=0;
    activeCeiling=Math.min(MAX_ACTIVE_TOTAL,activeCeiling+3);
    stats.concurrencyRecoveries++;
  }

  function startJob(lane,job){
    lane.active++;
    lane.started++;
    starts.push(Date.now());
    stats.started++;
    stats.maxObservedActive=Math.max(stats.maxObservedActive,totalActive());

    Promise.resolve()
      .then(()=>original.decide(job.request,job.context))
      .then(result=>{
        lane.completed++;
        stats.completed++;
        stats.lastError=null;
        stats.lastSuccessAt=Date.now();
        maybeRecoverConcurrency();
        job.resolve(result);
      })
      .catch(error=>{
        lane.failed++;
        stats.failed++;
        stats.lastError=String(error?.message||error);
        reduceConcurrency(error);
        job.reject(error);
      })
      .finally(()=>{
        lane.active=Math.max(0,lane.active-1);
        pump();
      });
  }

  function nextRunnableLane(){
    const perLane=laneCeiling();
    for(let offset=0;offset<LANE_COUNT;offset++){
      const idx=(rrCursor+offset)%LANE_COUNT;
      const lane=lanes[idx];
      if(lane.queue.length && lane.active<perLane){
        rrCursor=(idx+1)%LANE_COUNT;
        return lane;
      }
    }
    return null;
  }

  function pump(){
    const delay=nextRateDelay();
    if(delay>0){schedulePump(delay);return;}
    let guard=0;
    while(totalActive()<activeCeiling && totalQueued()>0 && guard++<MAX_ACTIVE_TOTAL*2){
      const rateDelay=nextRateDelay();
      if(rateDelay>0){schedulePump(rateDelay);break;}
      const lane=nextRunnableLane();
      if(!lane)break;
      startJob(lane,lane.queue.shift());
    }
  }

  class FullThroughputByokProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return typeof original.isConfigured==="function"?original.isConfigured():!!baseApi?.hasKey?.()}
    decide(request,context){
      if(!this.isConfigured())return Promise.reject(new Error("Typhoon API key is not set for this browser session"));
      if(totalQueued()>=MAX_QUEUE_TOTAL)return Promise.reject(new Error(`Typhoon BYOK queue full (${MAX_QUEUE_TOTAL})`));
      const lane=lanes[laneIndexFor(request)];
      stats.enqueued++;
      return new Promise((resolve,reject)=>{
        insertJob(lane,{request,context,resolve,reject,priority:0,enqueuedAt:performance.now()});
        pump();
      });
    }
    status(){
      prune();
      const upstream=typeof original.status==="function"?original.status():{};
      return {
        configured:this.isConfigured(),
        queueDepth:totalQueued(),
        active:totalActive(),
        activeCeiling,
        startsLastMinute:starts.length,
        lanes:lanes.map(w=>({name:w.name,active:w.active,queued:w.queue.length,started:w.started,completed:w.completed,failed:w.failed,maxQueue:w.maxQueue})),
        workers:lanes.map(w=>({name:w.name,active:w.active,queued:w.queue.length,started:w.started,completed:w.completed,failed:w.failed,maxQueue:w.maxQueue})),
        limits:{laneCount:LANE_COUNT,maxActiveTotal:MAX_ACTIVE_TOTAL,minActiveTotal:MIN_ACTIVE_TOTAL,maxCallsPerMinute:MAX_CALLS_PER_MINUTE,maxQueue:MAX_QUEUE_TOTAL},
        stats:{...stats},
        upstream
      };
    }
  }

  const dispatcher=new FullThroughputByokProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,dispatcher,{
    label:"Typhoon 2.5 · BYOK · full throughput",
    async:true,
    description:"Adaptive high-concurrency dispatcher: use available Typhoon capacity first, back off only after real rate-limit pressure"
  });

  if(baseApi){
    window.AstraLifeTyphoonBYOK=Object.freeze({
      ...baseApi,
      version:VERSION,
      status:()=>dispatcher.status(),
      queueDepth:()=>totalQueued()
    });
  }

  const clearBtn=document.getElementById("clearTyphoonKeyBtn");
  let statusEl=document.getElementById("typhoonApiStatus");
  if(!statusEl){
    statusEl=document.createElement("span");
    statusEl.id="typhoonApiStatus";
    statusEl.className="provider-badge";
    statusEl.style.whiteSpace="nowrap";
    statusEl.style.fontSize="11px";
    clearBtn?.insertAdjacentElement("afterend",statusEl);
  }

  function renderStatus(){
    const s=dispatcher.status();
    const upstreamStats=s.upstream?.stats||{};
    const successes=Number(upstreamStats.successes||0);
    const errors=Number(upstreamStats.errors||0)+Number(stats.failed||0);
    const sessionCount=Number(s.upstream?.sessions?.count||0);
    if(!s.configured){
      statusEl.textContent="Typhoon API · ยังไม่เปิด";
      statusEl.classList.remove("pending","error");
      return;
    }
    if(errors>0 && successes===0){
      const msg=String(stats.lastError||s.upstream?.stats?.lastError||"");
      statusEl.textContent=/fetch|network/i.test(msg)?"Typhoon API ✕ Network/CORS":`Typhoon API ✕ ${errors}`;
      statusEl.classList.add("error");statusEl.classList.remove("pending");
      return;
    }
    const laneText=s.lanes.map(w=>`${w.name}${w.active}/Q${w.queued}`).join(" ");
    const gate=window.AstraLifeLLMGate?.status?.();
    const gateText=gate?` · Real ${gate.stats.realCalls} · Reuse ${gate.stats.reuses}`:"";
    statusEl.textContent=`Typhoon ✓${successes} · Run ${s.active}/${s.activeCeiling} · Q${s.queueDepth} · ${laneText} · S${sessionCount}${gateText}`;
    statusEl.classList.toggle("pending",s.active>0||s.queueDepth>0);
    statusEl.classList.remove("error");
  }

  setInterval(renderStatus,350);
  renderStatus();

  window.AstraLifeTyphoonQueue=Object.freeze({
    version:VERSION,
    status:()=>dispatcher.status(),
    workerForAgent:agentId=>lanes[(Math.max(1,Number(agentId)||1)-1)%LANE_COUNT].name,
    laneForAgent:agentId=>lanes[(Math.max(1,Number(agentId)||1)-1)%LANE_COUNT].name,
    limits:Object.freeze({laneCount:LANE_COUNT,maxActiveTotal:MAX_ACTIVE_TOTAL,minActiveTotal:MIN_ACTIVE_TOTAL,maxCallsPerMinute:MAX_CALLS_PER_MINUTE,maxQueue:MAX_QUEUE_TOTAL})
  });
})();

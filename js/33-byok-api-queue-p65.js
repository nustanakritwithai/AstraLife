(() => {
  "use strict";

  const VERSION = "p6.6-three-workers-global-limiter";
  const PROVIDER_ID = "typhoon-byok";
  const WORKER_COUNT = 3;
  const SAFE_CALLS_PER_MINUTE = 165;
  const MAX_QUEUE_TOTAL = 120;

  const existing = runtime.registry.get(PROVIDER_ID);
  if(!existing?.adapter || typeof existing.adapter.decide !== "function")return;
  const original = existing.adapter;
  const baseApi = window.AstraLifeTyphoonBYOK;

  const workers = Array.from({length:WORKER_COUNT},(_,index)=>({
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
  const stats = {
    enqueued:0,
    started:0,
    completed:0,
    failed:0,
    maxObservedActive:0,
    maxObservedQueue:0,
    lastError:null,
    lastSuccessAt:null
  };

  const totalActive=()=>workers.reduce((sum,w)=>sum+w.active,0);
  const totalQueued=()=>workers.reduce((sum,w)=>sum+w.queue.length,0);

  function prune(now=Date.now()){
    const floor = now - 60000;
    while(starts.length && starts[0] <= floor)starts.shift();
  }

  function workerIndexFor(request){
    const id=Math.max(1,Number(request?.agent?.id)||1);
    return (id-1)%WORKER_COUNT;
  }

  function priorityFor(request){
    const selected = Number(runtime.selectedAgentId);
    const id = Number(request?.agent?.id);
    if(Number.isFinite(selected) && selected === id)return 1000;
    const self = request?.observation?.self || {};
    let score = 0;
    if(Number(self.hp) < 45)score += 120;
    if(Number(self.thirst) > 78)score += 90;
    if(Number(self.hunger) > 80)score += 70;
    return score;
  }

  function insertJob(worker,job){
    const p = priorityFor(job.request);
    job.priority = p;
    let i = worker.queue.length;
    while(i > 0 && worker.queue[i-1].priority < p)i--;
    worker.queue.splice(i,0,job);
    worker.maxQueue=Math.max(worker.maxQueue,worker.queue.length);
    stats.maxObservedQueue = Math.max(stats.maxObservedQueue,totalQueued());
  }

  function schedulePump(delayMs){
    if(timer)return;
    timer = setTimeout(()=>{timer=null;pumpAll();},Math.max(25,delayMs|0));
  }

  function nextRateDelay(now=Date.now()){
    prune(now);
    if(starts.length < SAFE_CALLS_PER_MINUTE)return 0;
    return Math.max(25,60000-(now-starts[0])+10);
  }

  function startJob(worker,job){
    worker.active=1;
    worker.started++;
    starts.push(Date.now());
    stats.started++;
    stats.maxObservedActive = Math.max(stats.maxObservedActive,totalActive());

    Promise.resolve()
      .then(()=>original.decide(job.request,job.context))
      .then(result=>{
        worker.completed++;
        stats.completed++;
        stats.lastError=null;
        stats.lastSuccessAt=Date.now();
        job.resolve(result);
      })
      .catch(error=>{
        worker.failed++;
        stats.failed++;
        stats.lastError=String(error?.message || error);
        job.reject(error);
      })
      .finally(()=>{
        worker.active=0;
        pumpAll();
      });
  }

  function pumpWorker(worker){
    if(worker.active || !worker.queue.length)return;
    const delay=nextRateDelay();
    if(delay>0){schedulePump(delay);return;}
    startJob(worker,worker.queue.shift());
  }

  function pumpAll(){
    const delay=nextRateDelay();
    if(delay>0){schedulePump(delay);return;}
    for(const worker of workers)pumpWorker(worker);
  }

  class ThreeWorkerByokProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return typeof original.isConfigured === "function" ? original.isConfigured() : !!baseApi?.hasKey?.()}
    decide(request,context){
      if(!this.isConfigured())return Promise.reject(new Error("Typhoon API key is not set for this browser session"));
      if(totalQueued() >= MAX_QUEUE_TOTAL)return Promise.reject(new Error(`Typhoon BYOK queue full (${MAX_QUEUE_TOTAL})`));
      const worker=workers[workerIndexFor(request)];
      stats.enqueued++;
      return new Promise((resolve,reject)=>{
        insertJob(worker,{request,context,resolve,reject,priority:0,enqueuedAt:performance.now()});
        pumpAll();
      });
    }
    status(){
      prune();
      const upstream = typeof original.status === "function" ? original.status() : {};
      return {
        configured:this.isConfigured(),
        queueDepth:totalQueued(),
        active:totalActive(),
        startsLastMinute:starts.length,
        workers:workers.map(w=>({name:w.name,active:w.active,queued:w.queue.length,started:w.started,completed:w.completed,failed:w.failed,maxQueue:w.maxQueue})),
        limits:{workerCount:WORKER_COUNT,maxActiveTotal:WORKER_COUNT,safeCallsPerMinute:SAFE_CALLS_PER_MINUTE,maxQueue:MAX_QUEUE_TOTAL},
        stats:{...stats},
        upstream
      };
    }
  }

  const queuedProvider = new ThreeWorkerByokProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,queuedProvider,{
    label:"Typhoon 2.5 · BYOK · 3 workers",
    async:true,
    description:"One API key, independent Agent sessions, three stable worker queues and one shared global rate limiter"
  });

  if(baseApi){
    window.AstraLifeTyphoonBYOK = Object.freeze({
      ...baseApi,
      version:VERSION,
      status:()=>queuedProvider.status(),
      queueDepth:()=>totalQueued()
    });
  }

  const clearBtn=document.getElementById("clearTyphoonKeyBtn");
  const statusEl=document.createElement("span");
  statusEl.id="typhoonApiStatus";
  statusEl.className="provider-badge";
  statusEl.style.whiteSpace="nowrap";
  statusEl.style.fontSize="11px";
  statusEl.textContent="Typhoon API · idle";
  clearBtn?.insertAdjacentElement("afterend",statusEl);

  function renderStatus(){
    const s=queuedProvider.status();
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
    const workerText=s.workers.map(w=>`${w.name}${w.active}/Q${w.queued}`).join(" ");
    const gate=window.AstraLifeLLMGate?.status?.();
    const gateText=gate?` · Real ${gate.stats.realCalls} · Reuse ${gate.stats.reuses}`:"";
    statusEl.textContent=`Typhoon ✓${successes} · ${workerText} · S${sessionCount}${gateText}`;
    statusEl.classList.toggle("pending",s.active>0||s.queueDepth>0);
    statusEl.classList.remove("error");
  }

  setInterval(renderStatus,350);
  renderStatus();

  window.AstraLifeTyphoonQueue = Object.freeze({
    version:VERSION,
    status:()=>queuedProvider.status(),
    workerForAgent:agentId=>workers[(Math.max(1,Number(agentId)||1)-1)%WORKER_COUNT].name,
    limits:Object.freeze({workerCount:WORKER_COUNT,maxActiveTotal:WORKER_COUNT,safeCallsPerMinute:SAFE_CALLS_PER_MINUTE,maxQueue:MAX_QUEUE_TOTAL})
  });
})();

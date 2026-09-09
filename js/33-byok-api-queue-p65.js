(() => {
  "use strict";

  const VERSION = "p6.5-byok-api-queue-independent-sessions";
  const PROVIDER_ID = "typhoon-byok";
  const MAX_ACTIVE = 3;
  const SAFE_CALLS_PER_MINUTE = 165;
  const MAX_QUEUE = 120;

  const existing = runtime.registry.get(PROVIDER_ID);
  if(!existing?.adapter || typeof existing.adapter.decide !== "function")return;
  const original = existing.adapter;
  const baseApi = window.AstraLifeTyphoonBYOK;

  const queue = [];
  const starts = [];
  let active = 0;
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

  function prune(now=Date.now()){
    const floor = now - 60000;
    while(starts.length && starts[0] <= floor)starts.shift();
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

  function insertJob(job){
    const p = priorityFor(job.request);
    job.priority = p;
    let i = queue.length;
    while(i > 0 && queue[i-1].priority < p)i--;
    queue.splice(i,0,job);
    stats.maxObservedQueue = Math.max(stats.maxObservedQueue,queue.length);
  }

  function schedulePump(delayMs){
    if(timer)return;
    timer = setTimeout(()=>{timer=null;pump();},Math.max(25,delayMs|0));
  }

  function nextRateDelay(now=Date.now()){
    prune(now);
    if(starts.length < SAFE_CALLS_PER_MINUTE)return 0;
    return Math.max(25,60000-(now-starts[0])+10);
  }

  function startJob(job){
    active++;
    starts.push(Date.now());
    stats.started++;
    stats.maxObservedActive = Math.max(stats.maxObservedActive,active);

    Promise.resolve()
      .then(()=>original.decide(job.request,job.context))
      .then(result=>{
        stats.completed++;
        stats.lastError=null;
        stats.lastSuccessAt=Date.now();
        job.resolve(result);
      })
      .catch(error=>{
        stats.failed++;
        stats.lastError=String(error?.message || error);
        job.reject(error);
      })
      .finally(()=>{
        active=Math.max(0,active-1);
        pump();
      });
  }

  function pump(){
    if(!queue.length)return;
    const delay = nextRateDelay();
    if(delay>0){schedulePump(delay);return;}
    while(active < MAX_ACTIVE && queue.length){
      const delayNow = nextRateDelay();
      if(delayNow>0){schedulePump(delayNow);break;}
      startJob(queue.shift());
    }
  }

  class QueuedByokProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return typeof original.isConfigured === "function" ? original.isConfigured() : !!baseApi?.hasKey?.()}
    decide(request,context){
      if(!this.isConfigured())return Promise.reject(new Error("Typhoon API key is not set for this browser session"));
      if(queue.length >= MAX_QUEUE)return Promise.reject(new Error(`Typhoon BYOK queue full (${MAX_QUEUE})`));
      stats.enqueued++;
      return new Promise((resolve,reject)=>{
        insertJob({request,context,resolve,reject,priority:0,enqueuedAt:performance.now()});
        pump();
      });
    }
    status(){
      prune();
      const upstream = typeof original.status === "function" ? original.status() : {};
      return {
        configured:this.isConfigured(),
        queueDepth:queue.length,
        active,
        startsLastMinute:starts.length,
        limits:{maxActive:MAX_ACTIVE,safeCallsPerMinute:SAFE_CALLS_PER_MINUTE,maxQueue:MAX_QUEUE},
        stats:{...stats},
        upstream
      };
    }
  }

  const queuedProvider = new QueuedByokProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,queuedProvider,{
    label:"Typhoon 2.5 · BYOK · independent Agents",
    async:true,
    description:"One API key, isolated per-Agent LLM sessions, queued fairly so excess Agents wait for real Typhoon capacity"
  });

  if(baseApi){
    window.AstraLifeTyphoonBYOK = Object.freeze({
      ...baseApi,
      version:VERSION,
      status:()=>queuedProvider.status(),
      queueDepth:()=>queue.length
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
    statusEl.textContent=`Typhoon API ✓${successes} · Run ${s.active} · Q ${s.queueDepth} · S ${sessionCount}`;
    statusEl.classList.toggle("pending",s.active>0||s.queueDepth>0);
    statusEl.classList.remove("error");
  }

  setInterval(renderStatus,350);
  renderStatus();

  window.AstraLifeTyphoonQueue = Object.freeze({
    version:VERSION,
    status:()=>queuedProvider.status(),
    limits:Object.freeze({maxActive:MAX_ACTIVE,safeCallsPerMinute:SAFE_CALLS_PER_MINUTE,maxQueue:MAX_QUEUE})
  });
})();

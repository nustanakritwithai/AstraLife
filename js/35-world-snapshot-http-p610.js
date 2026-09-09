(() => {
  "use strict";

  const VERSION="p6.10-world-snapshot-http-byok";
  const PROVIDER_ID="world-snapshot-http";
  const DEFAULT_ENDPOINT="https://dufgcgjhcgiefpdjxewp.supabase.co/functions/v1/astralife-world-snapshot";
  const MAX_RESPONSE_BYTES=900000;
  const MAX_BATCH_AGENTS=160;
  const FLUSH_DELAY_MS=0;

  let sessionKey="";
  const batches=new Map();
  let inFlight=0;
  const stats={
    snapshots:0,agentsRequested:0,agentsResolved:0,agentsMissing:0,
    errors:0,lastError:null,lastSuccessAt:null,lastSnapshotId:null,lastBatchSize:0
  };

  const clone=v=>JSON.parse(JSON.stringify(v));
  const safeText=(v,max)=>String(v??"").replace(/\s+/g," ").trim().slice(0,max);
  const endpoint=()=>String(runtime.providerEndpoint||DEFAULT_ENDPOINT).trim();
  const configured=()=>/^https:\/\//i.test(endpoint())&&sessionKey.length>=12;
  const batchKeyFor=request=>`${request.simulation.id}:${request.simulation.tick}:${runtime.decisionRouter.epoch}`;

  function compactAgentRequest(request){
    const o=request.observation||{};
    const m=request.memory||{};
    return {
      requestId:String(request.requestId),
      sessionId:String(request.sessionId),
      agentId:Number(request.agent.id),
      agent:{
        id:Number(request.agent.id),name:safeText(request.agent.name,40),role:safeText(request.agent.role,24),
        capacity:Number(request.agent.capacity)||0,capabilities:clone(request.agent.capabilities||{})
      },
      self:clone(o.self||{}),
      environment:clone(o.environment||{}),
      camp:clone(o.camp||{}),
      visibleResources:(o.visibleResources||[]).slice(0,8).map(clone),
      nearbyAgents:(o.nearbyAgents||[]).slice(0,6).map(clone),
      messages:(o.messages||[]).slice(0,4).map(msg=>({
        id:msg.id,from:msg.from,to:msg.to,intent:msg.intent,urgency:msg.urgency,
        text:safeText(msg.text,120),facts:(msg.facts||[]).slice(0,3).map(clone)
      })),
      memory:{
        currentGoal:safeText(m.currentGoal,60),goalReason:safeText(m.goalReason,120),currentPlan:safeText(m.currentPlan,140),
        beliefStock:clone(m.beliefStock||{}),knownShelters:Number(m.knownShelters)||0,failedActions:Number(m.failedActions)||0,
        symbolicFacts:(m.symbolicFacts||[]).slice(0,10).map(f=>({key:f.key,value:clone(f.value),confidence:f.confidence,lastSeenTick:f.lastSeenTick,source:f.source})),
        recentEpisodes:(m.recentEpisodes||[]).slice(-4).map(e=>({tick:e.tick,kind:e.kind,text:safeText(e.text,120)}))
      },
      actionContract:{
        allowedTypes:[...(request.actionContract?.allowedTypes||[])],
        limits:clone(request.actionContract?.limits||{})
      }
    };
  }

  function snapshotEnvelope(batch){
    const rows=[...batch.entries.values()];
    const first=rows[0]?.request;
    const tick=Number(first?.simulation?.tick||0);
    const snapshotId=`${first?.simulation?.id||"world"}:${tick}:${batch.epoch}`;
    batch.snapshotId=snapshotId;
    return {
      protocol:"astralife.world-snapshot-request.p610",
      identity:{
        simulationId:String(first.simulation.id),runEpoch:batch.epoch,tick,snapshotId,
        deadlineTick:tick+CONFIG.maxDecisionAge
      },
      world:{
        simulationId:String(first.simulation.id),seed:String(first.simulation.seed),tick,day:first.simulation.day,alive:first.simulation.alive,
        environment:clone(first.observation?.environment||{}),
        camp:clone(first.observation?.camp||{})
      },
      agents:rows.map(row=>compactAgentRequest(row.request))
    };
  }

  function validateEnvelope(data,batch,payload){
    const id=data?.identity||{};
    if(data?.protocol!=="astralife.world-snapshot-response.p610")throw new Error("P6.10 snapshot response protocol mismatch");
    if(String(id.simulationId)!==String(payload.identity.simulationId))throw new Error("P6.10 simulationId mismatch");
    if(Number(id.runEpoch)!==Number(batch.epoch)||runtime.decisionRouter.epoch!==batch.epoch)throw new Error("P6.10 stale runtime epoch");
    if(Number(id.tick)!==Number(payload.identity.tick))throw new Error("P6.10 snapshot tick mismatch");
    if(String(id.snapshotId)!==String(payload.identity.snapshotId))throw new Error("P6.10 snapshotId mismatch");
    if(!Array.isArray(data.decisions))throw new Error("P6.10 decisions[] missing");
  }

  function toDecisionResponse(row,request,providerModel){
    const allowed=new Set(request.actionContract?.allowedTypes||[ACTION.WAIT]);
    const rawAction=row?.action&&typeof row.action==="object"?row.action:{type:ACTION.WAIT,payload:{}};
    const type=allowed.has(rawAction.type)?rawAction.type:ACTION.WAIT;
    const payload=rawAction.payload&&typeof rawAction.payload==="object"&&!Array.isArray(rawAction.payload)?clone(rawAction.payload):{};
    const goal=safeText(row?.goal||request.memory.currentGoal||"orient",80)||"orient";
    const reason=safeText(row?.reason||"world snapshot brain decision",180);
    const plan=safeText(row?.plan||type,220);
    const thought=safeText(row?.thought||reason||plan||goal,140);
    return {
      protocol:PROTOCOL.decisionResponse,
      requestId:request.requestId,
      agentId:request.agent.id,
      tick:request.simulation.tick,
      provider:PROVIDER_ID,
      decision:{
        action:{protocol:PROTOCOL.action,type,payload:type===ACTION.WAIT?{}:payload},
        cognition:{goal,reason,plan,thought},thought,reason,
        confidence:clamp(Number(row?.confidence)||.55,0,1),
        replanAfterTicks:clamp(Math.floor(Number(row?.replanAfterTicks)||12),1,120)
      },
      diagnostics:{engine:"world-snapshot-http",snapshotId:row?.snapshotId||null,providerModel:providerModel||null,keyPersistence:"memory-only"}
    };
  }

  async function dispatchBatch(batch){
    if(batch.dispatched)return;
    batch.dispatched=true;
    const payload=snapshotEnvelope(batch);
    if(payload.agents.length>MAX_BATCH_AGENTS){
      const error=new Error(`P6.10 snapshot agent cap exceeded (${payload.agents.length}/${MAX_BATCH_AGENTS})`);
      for(const row of batch.entries.values())row.reject(error);
      batches.delete(batch.key);return;
    }
    if(!configured()){
      const error=new Error("World Snapshot HTTP endpoint/API key is not configured");
      for(const row of batch.entries.values())row.reject(error);
      batches.delete(batch.key);return;
    }

    stats.snapshots++;stats.agentsRequested+=payload.agents.length;stats.lastSnapshotId=payload.identity.snapshotId;stats.lastBatchSize=payload.agents.length;
    inFlight++;
    try{
      const controller=new AbortController();
      const timer=setTimeout(()=>controller.abort(),CONFIG.providerTimeoutMs);
      let response;
      try{
        response=await fetch(endpoint(),{
          method:"POST",
          headers:{"content-type":"application/json","accept":"application/json","x-typhoon-key":sessionKey},
          body:JSON.stringify(payload),signal:controller.signal,credentials:"omit",cache:"no-store",referrerPolicy:"no-referrer"
        });
      }finally{clearTimeout(timer)}
      const text=await response.text();
      if(text.length>MAX_RESPONSE_BYTES)throw new Error("P6.10 snapshot response too large");
      if(!response.ok)throw new Error(`P6.10 HTTP ${response.status}: ${text.slice(0,200)}`);
      let data;try{data=JSON.parse(text)}catch(error){throw new Error(`P6.10 invalid JSON: ${error.message}`)}
      validateEnvelope(data,batch,payload);
      const byAgent=new Map(data.decisions.map(row=>[Number(row.agentId),row]));
      for(const [agentId,entry] of batch.entries){
        const row=byAgent.get(Number(agentId));
        if(!row||String(row.requestId)!==String(entry.request.requestId)){
          stats.agentsMissing++;entry.reject(new Error(`P6.10 missing decision for Agent ${agentId}`));continue;
        }
        stats.agentsResolved++;
        entry.resolve(toDecisionResponse({...row,snapshotId:payload.identity.snapshotId},entry.request,data.providerModel));
      }
      stats.lastError=null;stats.lastSuccessAt=Date.now();
    }catch(error){
      stats.errors++;stats.lastError=String(error?.message||error);
      for(const row of batch.entries.values())row.reject(error instanceof Error?error:new Error(String(error)));
    }finally{
      inFlight=Math.max(0,inFlight-1);batches.delete(batch.key);
    }
  }

  class WorldSnapshotHttpProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return configured()}
    decide(request,context){
      if(!configured())return Promise.reject(new Error("World Snapshot HTTP endpoint/API key is not configured"));
      const key=batchKeyFor(request);
      let batch=batches.get(key);
      if(!batch){
        batch={key,epoch:runtime.decisionRouter.epoch,entries:new Map(),dispatched:false,timer:null,snapshotId:null};
        batches.set(key,batch);
        batch.timer=setTimeout(()=>dispatchBatch(batch),FLUSH_DELAY_MS);
      }
      return new Promise((resolve,reject)=>{
        batch.entries.set(Number(request.agent.id),{request,context,resolve,reject});
      });
    }
    status(){return {version:VERSION,configured:configured(),endpoint:endpoint(),keyConfigured:sessionKey.length>=12,inFlight,pendingSnapshots:batches.size,stats:{...stats}}}
  }

  const provider=new WorldSnapshotHttpProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,provider,{
    label:"World Snapshot HTTP · BYOK",
    async:true,
    description:"Collect all Agent decisions for one world tick, send one HTTP snapshot request, then fan the decision batch back through the normal Validator/Resolver path"
  });

  if(!runtime.providerEndpoint)runtime.setProviderEndpoint(DEFAULT_ENDPOINT);

  const select=document.getElementById("providerSelect");
  if(select&&!select.querySelector(`option[value="provider:${PROVIDER_ID}"]`)){
    const option=document.createElement("option");option.value=`provider:${PROVIDER_ID}`;option.textContent="World Snapshot HTTP · 1 call/tick";select.appendChild(option);
  }

  const endpointInput=document.getElementById("endpointInput");
  const keyInput=document.createElement("input");
  keyInput.id="snapshotApiKeyInput";keyInput.type="password";keyInput.autocomplete="off";keyInput.spellcheck=false;
  keyInput.placeholder="Snapshot API key · session only";keyInput.setAttribute("aria-label","Snapshot API key for this browser session only");
  const useBtn=document.createElement("button");useBtn.id="useSnapshotBtn";useBtn.textContent="ใช้ Snapshot AI";
  const clearBtn=document.createElement("button");clearBtn.id="clearSnapshotKeyBtn";clearBtn.textContent="ล้าง Snapshot Key";
  const badge=document.createElement("span");badge.id="snapshotApiStatus";badge.className="provider-badge";badge.style.whiteSpace="nowrap";badge.style.fontSize="11px";

  useBtn.onclick=()=>{
    const key=String(keyInput.value||"").trim();
    if(key.length<12){keyInput.setCustomValidity("ใส่ API key ก่อน");keyInput.reportValidity();return;}
    keyInput.setCustomValidity("");sessionKey=key;keyInput.value="";
    runtime.setProviderEndpoint(DEFAULT_ENDPOINT);
    runtime.setProviderMode(`provider:${PROVIDER_ID}`);if(select)select.value=`provider:${PROVIDER_ID}`;updateHud();
  };
  clearBtn.onclick=()=>{sessionKey="";keyInput.value="";if(runtime.decisionRouter.mode===`provider:${PROVIDER_ID}`)runtime.setProviderMode(PROVIDER_MODE.LOCAL);if(select)select.value=PROVIDER_MODE.LOCAL;updateHud();};

  if(endpointInput){
    endpointInput.insertAdjacentElement("afterend",badge);
    endpointInput.insertAdjacentElement("afterend",clearBtn);
    endpointInput.insertAdjacentElement("afterend",useBtn);
    endpointInput.insertAdjacentElement("afterend",keyInput);
  }

  function renderStatus(){
    const s=provider.status(),st=s.stats;
    if(!s.keyConfigured){badge.textContent="Snapshot AI · ยังไม่ใส่ Key";badge.classList.remove("pending","error");return;}
    if(st.errors>0&&st.agentsResolved===0){badge.textContent=`Snapshot AI ✕ ${st.errors}`;badge.classList.add("error");return;}
    badge.textContent=`Snapshot ✓${st.snapshots} · Batch ${st.lastBatchSize} · Agents ${st.agentsResolved} · Net ${st.snapshots}`;
    badge.classList.toggle("pending",s.inFlight>0||s.pendingSnapshots>0);badge.classList.remove("error");
  }
  setInterval(renderStatus,350);renderStatus();

  window.AstraLifeWorldSnapshotHTTP=Object.freeze({
    version:VERSION,providerId:PROVIDER_ID,mode:`provider:${PROVIDER_ID}`,
    setKey:key=>{sessionKey=String(key||"").trim();return configured()},clearKey:()=>{sessionKey="";return true},hasKey:()=>sessionKey.length>=12,
    configure:url=>runtime.setProviderEndpoint(String(url||"").trim()),enable:()=>{if(!configured())throw new Error("Snapshot endpoint/API key not configured");runtime.setProviderMode(`provider:${PROVIDER_ID}`);return runtime.decisionRouter.mode},
    disable:()=>{runtime.setProviderMode(PROVIDER_MODE.LOCAL);return runtime.decisionRouter.mode},status:()=>provider.status()
  });
})();

(() => {
  "use strict";

  const VERSION="p6.10-direct-world-snapshot-byok";
  const PROVIDER_ID="world-snapshot-byok";
  const MODEL="typhoon-v2.5-30b-a3b-instruct";
  const ENDPOINT="https://api.opentyphoon.ai/v1/chat/completions";
  const MAX_BATCH_AGENTS=160;
  const MAX_RESPONSE_BYTES=900000;
  const FLUSH_DELAY_MS=0;
  const MAX_OUTPUT_TOKENS=7000;

  let sessionKey="";
  const batches=new Map();
  let inFlight=0;
  const stats={
    snapshots:0,networkCalls:0,agentsRequested:0,agentsResolved:0,agentsMissing:0,
    errors:0,lastError:null,lastSuccessAt:null,lastSnapshotId:null,lastBatchSize:0,
    lastModel:null,lastUsage:null
  };

  const clone=v=>JSON.parse(JSON.stringify(v));
  const safeText=(v,max)=>String(v??"").replace(/\s+/g," ").trim().slice(0,max);
  const configured=()=>sessionKey.length>=12;
  const batchKeyFor=request=>`${request.simulation.id}:${request.simulation.tick}:${runtime.decisionRouter.epoch}`;

  function stripFence(text){
    const s=String(text||"").trim();
    if(!s.startsWith("```"))return s;
    return s.replace(/^```(?:json)?\s*/i,"").replace(/\s*```$/i,"").trim();
  }

  function compactAgentRequest(request){
    const o=request.observation||{},m=request.memory||{};
    return {
      agentId:Number(request.agent.id),
      role:safeText(request.agent.role,20),
      capacity:Number(request.agent.capacity)||0,
      self:{
        x:o.self?.x,y:o.self?.y,hp:o.self?.hp,hunger:o.self?.hunger,thirst:o.self?.thirst,
        energy:o.self?.energy,carry:clone(o.self?.carry||{})
      },
      camp:{
        visible:!!o.camp?.visible,x:o.camp?.x,y:o.camp?.y,distance:o.camp?.distance,
        stock:clone(o.camp?.stock||{}),shelter:o.camp?.shelter
      },
      environment:clone(o.environment||{}),
      resources:(o.visibleResources||[]).slice(0,6).map(r=>({id:r.id,type:r.type,x:r.x,y:r.y,distance:r.distance,amount:r.amount})),
      peers:(o.nearbyAgents||[]).slice(0,5).map(p=>({id:p.id,role:p.role,x:p.x,y:p.y,distance:p.distance,hpBand:p.hpBand})),
      messages:(o.messages||[]).slice(0,3).map(msg=>({
        id:msg.id,from:msg.from,intent:msg.intent,urgency:msg.urgency,text:safeText(msg.text,90)
      })),
      memory:{
        goal:safeText(m.currentGoal,45),reason:safeText(m.goalReason,80),plan:safeText(m.currentPlan,100),
        beliefStock:clone(m.beliefStock||{}),knownShelters:Number(m.knownShelters)||0,failedActions:Number(m.failedActions)||0,
        facts:(m.symbolicFacts||[]).slice(0,7).map(f=>({key:f.key,value:clone(f.value),confidence:f.confidence}))
      },
      allowedTypes:[...(request.actionContract?.allowedTypes||[])]
    };
  }

  function snapshotFor(batch){
    const rows=[...batch.entries.values()];
    const first=rows[0]?.request;
    const tick=Number(first?.simulation?.tick||0);
    const snapshotId=`${first?.simulation?.id||"world"}:${tick}:${batch.epoch}`;
    batch.snapshotId=snapshotId;
    return {
      snapshotId,
      simulationId:String(first.simulation.id),
      seed:String(first.simulation.seed),
      tick,day:first.simulation.day,alive:first.simulation.alive,
      world:{environment:clone(first.observation?.environment||{}),camp:clone(first.observation?.camp||{})},
      agents:rows.map(row=>compactAgentRequest(row.request))
    };
  }

  function promptFor(snapshot){
    return [
      "You are the World Snapshot Brain for AstraLife.",
      "One request contains many independent agents from one authoritative world tick.",
      "Return compact JSON only. Do not reveal chain-of-thought.",
      "Return exactly one decision for EVERY agentId in the snapshot.",
      "Use only each agent's supplied observation/memory and choose only from that agent's allowedTypes.",
      "Never mutate world state directly; the client Validator and Resolver are authoritative.",
      "Keep thought <= 80 chars, goal <= 40, reason <= 90, plan <= 100.",
      "Output shape:",
      '{"decisions":[{"agentId":1,"action":{"type":"WAIT","payload":{}},"thought":"short public thought","goal":"short goal","reason":"observable reason","plan":"short plan","confidence":0.7,"replanAfterTicks":12}]}',
      "Payloads: MOVE{x,y,speed?}; GATHER{resourceId,resourceType,carryType}; CONSUME{resource}; HEAL{targetAgentId}; SHARE{intent,facts,targetAgentId?,replyTo?,urgency?,text?}; DEPOSIT/REST/BUILD/WAIT use {}.",
      "World snapshot:",
      JSON.stringify(snapshot)
    ].join("\n");
  }

  function toDecisionResponse(row,request,snapshotId,providerModel){
    const allowed=new Set(request.actionContract?.allowedTypes||[ACTION.WAIT]);
    const rawAction=row?.action&&typeof row.action==="object"?row.action:{type:ACTION.WAIT,payload:{}};
    const type=allowed.has(rawAction.type)?rawAction.type:ACTION.WAIT;
    const payload=rawAction.payload&&typeof rawAction.payload==="object"&&!Array.isArray(rawAction.payload)?clone(rawAction.payload):{};
    const goal=safeText(row?.goal||request.memory.currentGoal||"orient",80)||"orient";
    const reason=safeText(row?.reason||"world snapshot decision",180);
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
        replanAfterTicks:clamp(Math.floor(Number(row?.replanAfterTicks)||12),2,120)
      },
      diagnostics:{
        engine:"direct-browser-world-snapshot",snapshotId,model:providerModel||MODEL,
        keyPersistence:"memory-only",batchNetworkCall:true
      }
    };
  }

  async function dispatchBatch(batch){
    if(batch.dispatched)return;
    batch.dispatched=true;
    const snapshot=snapshotFor(batch);
    const entries=[...batch.entries.entries()];
    if(snapshot.agents.length>MAX_BATCH_AGENTS){
      const error=new Error(`P6.10 snapshot agent cap exceeded (${snapshot.agents.length}/${MAX_BATCH_AGENTS})`);
      for(const [,entry] of entries)entry.reject(error);
      batches.delete(batch.key);return;
    }
    if(!configured()){
      const error=new Error("World Snapshot API key is not configured");
      for(const [,entry] of entries)entry.reject(error);
      batches.delete(batch.key);return;
    }

    stats.snapshots++;stats.networkCalls++;stats.agentsRequested+=snapshot.agents.length;
    stats.lastSnapshotId=snapshot.snapshotId;stats.lastBatchSize=snapshot.agents.length;
    inFlight++;
    try{
      const controller=new AbortController();
      const timer=setTimeout(()=>controller.abort(),CONFIG.providerTimeoutMs);
      let response;
      try{
        response=await fetch(ENDPOINT,{
          method:"POST",
          headers:{"authorization":`Bearer ${sessionKey}`,"content-type":"application/json","accept":"application/json"},
          body:JSON.stringify({
            model:MODEL,
            messages:[
              {role:"system",content:"Return only compact JSON decisions for every AstraLife agent in the supplied world snapshot. Never expose hidden chain-of-thought."},
              {role:"user",content:promptFor(snapshot)}
            ],
            temperature:.2,max_tokens:MAX_OUTPUT_TOKENS,stream:false
          }),
          signal:controller.signal,credentials:"omit",cache:"no-store",referrerPolicy:"no-referrer"
        });
      }finally{clearTimeout(timer)}

      const text=await response.text();
      if(text.length>MAX_RESPONSE_BYTES)throw new Error("P6.10 Typhoon response too large");
      if(!response.ok)throw new Error(`P6.10 Typhoon HTTP ${response.status}: ${text.slice(0,220)}`);

      let completion;try{completion=JSON.parse(text)}catch(error){throw new Error(`P6.10 invalid API JSON: ${error.message}`)}
      const content=completion?.choices?.[0]?.message?.content;
      if(typeof content!=="string")throw new Error("P6.10 Typhoon response content missing");
      let parsed;try{parsed=JSON.parse(stripFence(content))}catch(error){throw new Error(`P6.10 snapshot JSON invalid: ${error.message}`)}
      const decisions=Array.isArray(parsed?.decisions)?parsed.decisions:[];
      const byAgent=new Map();
      for(const row of decisions){
        const id=Number(row?.agentId);
        if(Number.isInteger(id)&&!byAgent.has(id))byAgent.set(id,row);
      }

      for(const [agentId,entry] of entries){
        let row=byAgent.get(Number(agentId));
        if(!row){
          stats.agentsMissing++;
          row={agentId,action:{type:ACTION.WAIT,payload:{}},thought:"",goal:entry.request.memory.currentGoal,reason:"snapshot omitted this agent",plan:"WAIT",confidence:.35,replanAfterTicks:2};
        }
        stats.agentsResolved++;
        entry.resolve(toDecisionResponse(row,entry.request,snapshot.snapshotId,completion?.model||MODEL));
      }
      stats.lastModel=completion?.model||MODEL;stats.lastUsage=completion?.usage||null;
      stats.lastError=null;stats.lastSuccessAt=Date.now();
    }catch(error){
      stats.errors++;stats.lastError=String(error?.message||error);
      for(const [,entry] of entries)entry.reject(error instanceof Error?error:new Error(String(error)));
    }finally{
      inFlight=Math.max(0,inFlight-1);batches.delete(batch.key);
    }
  }

  class WorldSnapshotByokProvider{
    constructor(){this.id=PROVIDER_ID}
    isConfigured(){return configured()}
    decide(request,context){
      if(!configured())return Promise.reject(new Error("World Snapshot API key is not configured"));
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
    status(){
      return {version:VERSION,configured:configured(),endpoint:ENDPOINT,model:MODEL,keyConfigured:sessionKey.length>=12,inFlight,pendingSnapshots:batches.size,stats:{...stats}};
    }
  }

  const provider=new WorldSnapshotByokProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,provider,{
    label:"World Snapshot · Direct BYOK",
    async:true,
    description:"Collect all Agent requests for one tick, call Typhoon directly once from the browser, then fan decisions back through Validator/Resolver"
  });

  const select=document.getElementById("providerSelect");
  if(select&&!select.querySelector(`option[value="provider:${PROVIDER_ID}"]`)){
    const option=document.createElement("option");
    option.value=`provider:${PROVIDER_ID}`;option.textContent="World Snapshot · Direct · 1 call/tick";select.appendChild(option);
  }

  const endpointInput=document.getElementById("endpointInput");
  const keyInput=document.createElement("input");
  keyInput.id="snapshotApiKeyInput";keyInput.type="password";keyInput.autocomplete="off";keyInput.spellcheck=false;
  keyInput.placeholder="Typhoon API key · Snapshot · session only";
  keyInput.setAttribute("aria-label","Typhoon API key for direct world snapshot mode");
  const useBtn=document.createElement("button");useBtn.id="useSnapshotBtn";useBtn.textContent="ใช้ Snapshot AI";
  const clearBtn=document.createElement("button");clearBtn.id="clearSnapshotKeyBtn";clearBtn.textContent="ล้าง Snapshot Key";
  const badge=document.createElement("span");badge.id="snapshotApiStatus";badge.className="provider-badge";badge.style.whiteSpace="nowrap";badge.style.fontSize="11px";

  useBtn.onclick=()=>{
    const key=String(keyInput.value||"").trim();
    if(key.length<12){keyInput.setCustomValidity("ใส่ Typhoon API key ก่อน");keyInput.reportValidity();return;}
    keyInput.setCustomValidity("");sessionKey=key;keyInput.value="";
    runtime.setProviderMode(`provider:${PROVIDER_ID}`);
    if(select)select.value=`provider:${PROVIDER_ID}`;
    updateHud();
  };
  clearBtn.onclick=()=>{
    sessionKey="";keyInput.value="";
    if(runtime.decisionRouter.mode===`provider:${PROVIDER_ID}`)runtime.setProviderMode(PROVIDER_MODE.LOCAL);
    if(select)select.value=PROVIDER_MODE.LOCAL;updateHud();
  };

  if(endpointInput){
    endpointInput.insertAdjacentElement("afterend",badge);
    endpointInput.insertAdjacentElement("afterend",clearBtn);
    endpointInput.insertAdjacentElement("afterend",useBtn);
    endpointInput.insertAdjacentElement("afterend",keyInput);
  }

  function renderStatus(){
    const s=provider.status(),st=s.stats;
    if(!s.keyConfigured){badge.textContent="Snapshot AI · ยังไม่ใส่ Key";badge.classList.remove("pending","error");return;}
    if(st.errors>0&&st.agentsResolved===0){
      badge.textContent=/fetch|network|cors/i.test(String(st.lastError||""))?"Snapshot AI ✕ Network/CORS":`Snapshot AI ✕ ${st.errors}`;
      badge.classList.add("error");return;
    }
    badge.textContent=`Snapshot ✓${st.snapshots} · Batch ${st.lastBatchSize} · Agents ${st.agentsResolved} · Net ${st.networkCalls}`;
    badge.classList.toggle("pending",s.inFlight>0||s.pendingSnapshots>0);badge.classList.remove("error");
  }
  setInterval(renderStatus,350);renderStatus();

  window.AstraLifeWorldSnapshot=Object.freeze({
    version:VERSION,providerId:PROVIDER_ID,mode:`provider:${PROVIDER_ID}`,endpoint:ENDPOINT,model:MODEL,
    setKey:key=>{sessionKey=String(key||"").trim();return configured()},
    clearKey:()=>{sessionKey="";return true},hasKey:()=>sessionKey.length>=12,
    enable:()=>{if(!configured())throw new Error("Snapshot API key not configured");runtime.setProviderMode(`provider:${PROVIDER_ID}`);return runtime.decisionRouter.mode},
    disable:()=>{runtime.setProviderMode(PROVIDER_MODE.LOCAL);return runtime.decisionRouter.mode},
    status:()=>provider.status()
  });
})();

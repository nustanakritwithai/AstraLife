(() => {
  "use strict";

  const PROVIDER_ID = "typhoon-byok";
  const MODEL = "typhoon-v2.5-30b-a3b-instruct";
  const ENDPOINT = "https://api.opentyphoon.ai/v1/chat/completions";
  const MAX_CONCURRENT = 3;
  const MAX_CALLS_PER_MINUTE = 180;
  const MAX_RETRIES = 1;
  let sessionKey = "";

  const calls = [];
  const stats = {calls:0,successes:0,retries:0,rateLimited:0,errors:0,lastError:null,lastModel:null};
  const prune = () => {
    const floor = Date.now() - 60000;
    while (calls.length && calls[0] < floor) calls.shift();
  };
  const stripFence = text => {
    const trimmed = String(text || "").trim();
    if (!trimmed.startsWith("```")) return trimmed;
    return trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
  };
  const safeText = (value, max) => String(value ?? "").slice(0, max);
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

  function compactRequest(request){
    const copy = cloneJson(request);
    if (copy?.memory?.recentEpisodes?.length > 8) copy.memory.recentEpisodes = copy.memory.recentEpisodes.slice(-8);
    if (copy?.memory?.symbolicFacts?.length > 18) copy.memory.symbolicFacts = copy.memory.symbolicFacts.slice(0,18);
    if (copy?.observation?.messages?.length > 8) copy.observation.messages = copy.observation.messages.slice(-8);
    return copy;
  }

  function promptFor(request){
    return [
      "You are the decision engine for one AstraLife agent.",
      "Use ONLY the supplied observation, memory, beliefs and action contract. Never infer hidden world state.",
      "Return one compact JSON object only. Do not reveal chain-of-thought.",
      `Allowed action types: ${(request.actionContract?.allowedTypes || ["WAIT"]).join(", ")}`,
      'Return shape: {"action":{"type":"WAIT","payload":{}},"goal":"short goal","reason":"short observable reason","plan":"short plan","confidence":0.7,"replanAfterTicks":12}',
      "Payloads: MOVE{x,y,speed?}; GATHER{resourceId,resourceType,carryType}; CONSUME{resource}; HEAL{targetAgentId}; SHARE{intent,facts,targetAgentId?,replyTo?,urgency?,text?}; DEPOSIT/REST/BUILD/WAIT use {}.",
      "Keep confidence 0..1 and replanAfterTicks 1..120.",
      JSON.stringify(compactRequest(request))
    ].join("\n");
  }

  function normalize(raw, request){
    const allowed = new Set(request.actionContract?.allowedTypes || [ACTION.WAIT]);
    const src = isPlainObject(raw) ? raw : {};
    const a = isPlainObject(src.action) ? src.action : {type:ACTION.WAIT,payload:{}};
    const type = allowed.has(a.type) ? a.type : ACTION.WAIT;
    const payload = isPlainObject(a.payload) ? cloneJson(a.payload) : {};
    const goal = safeText(src.goal || request.memory.currentGoal || "orient", 80) || "orient";
    const reason = safeText(src.reason || "Typhoon chose an action from the visible state", 180);
    const plan = safeText(src.plan || type, 220);
    const confidence = clamp(Number(src.confidence) || .5, 0, 1);
    const replanAfterTicks = clamp(Math.floor(Number(src.replanAfterTicks) || 18), 1, 120);
    return {
      protocol: PROTOCOL.decisionResponse,
      requestId: request.requestId,
      agentId: request.agent.id,
      tick: request.simulation.tick,
      provider: PROVIDER_ID,
      decision: {
        action: {protocol:PROTOCOL.action,type,payload:type===ACTION.WAIT?{}:payload},
        cognition:{goal,reason,plan},
        reason,confidence,replanAfterTicks
      },
      diagnostics:{engine:"opentyphoon-direct-byok",model:MODEL,keyPersistence:"memory-only"}
    };
  }

  class TyphoonByokProvider {
    constructor(){this.id=PROVIDER_ID;this.inFlight=0}
    isConfigured(){return sessionKey.length >= 12}
    async decide(request){
      if (!this.isConfigured()) throw new Error("Typhoon API key is not set for this browser session");
      prune();
      if (this.inFlight >= MAX_CONCURRENT) throw new Error(`Typhoon BYOK concurrency cap reached (${MAX_CONCURRENT})`);
      if (calls.length >= MAX_CALLS_PER_MINUTE) throw new Error(`Typhoon BYOK calls/min cap reached (${MAX_CALLS_PER_MINUTE})`);
      const startEpoch = runtime.decisionRouter.epoch;
      const startSession = request.sessionId;
      const startAgent = request.agent.id;
      calls.push(Date.now()); stats.calls++; this.inFlight++;
      try {
        let lastError = null;
        for (let attempt=0; attempt<=MAX_RETRIES; attempt++) {
          try {
            const response = await fetch(ENDPOINT, {
              method:"POST",
              headers:{"authorization":`Bearer ${sessionKey}`,"content-type":"application/json","accept":"application/json"},
              body:JSON.stringify({
                model:MODEL,
                messages:[
                  {role:"system",content:"Return only the requested compact JSON decision. Never expose hidden chain-of-thought."},
                  {role:"user",content:promptFor(request)}
                ],
                temperature:.2,
                max_tokens:520,
                stream:false
              }),
              credentials:"omit",cache:"no-store",referrerPolicy:"no-referrer"
            });
            const text = await response.text();
            if (response.status === 429) {
              stats.rateLimited++;
              if (attempt < MAX_RETRIES) {stats.retries++; await sleep(450); continue;}
              throw new Error("Typhoon HTTP 429 after bounded retry");
            }
            if (!response.ok) throw new Error(`Typhoon HTTP ${response.status}: ${text.slice(0,160)}`);
            let completion;
            try {completion=JSON.parse(text)} catch(error){throw new Error(`Typhoon API JSON invalid: ${error.message}`)}
            const content = completion?.choices?.[0]?.message?.content;
            if (typeof content !== "string") throw new Error("Typhoon response content missing");
            let decision;
            try {decision=JSON.parse(stripFence(content))} catch(error){throw new Error(`Typhoon decision JSON invalid: ${error.message}`)}
            if (runtime.decisionRouter.epoch !== startEpoch) throw new Error("Typhoon response rejected after runtime reset/epoch change");
            const current = runtime.state.agentById.get(startAgent);
            if (!current || current.runtime.providerSessionId !== startSession) throw new Error("Typhoon response rejected after agent/session change");
            stats.successes++;stats.lastError=null;stats.lastModel=completion?.model || MODEL;
            return normalize(decision,request);
          } catch(error) {
            lastError = error instanceof Error ? error : new Error(String(error));
            if (attempt < MAX_RETRIES && /fetch|network/i.test(lastError.message)) {stats.retries++;await sleep(450);continue;}
            throw lastError;
          }
        }
        throw lastError || new Error("Typhoon request failed");
      } catch(error) {
        stats.errors++;stats.lastError=String(error?.message || error);throw error;
      } finally {
        this.inFlight=Math.max(0,this.inFlight-1);
      }
    }
    status(){prune();return {configured:this.isConfigured(),model:MODEL,endpoint:ENDPOINT,inFlight:this.inFlight,callsLastMinute:calls.length,limits:{maxConcurrent:MAX_CONCURRENT,maxCallsPerMinute:MAX_CALLS_PER_MINUTE,maxRetries:MAX_RETRIES},stats:{...stats}}}
  }

  const provider = new TyphoonByokProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,provider,{label:"Typhoon 2.5 · BYOK (session only)",async:true,description:"Direct browser test provider; API key stays only in page memory"});

  const endpointInput = document.getElementById("endpointInput");
  const keyInput = document.createElement("input");
  keyInput.id = "typhoonKeyInput";
  keyInput.type = "password";
  keyInput.autocomplete = "off";
  keyInput.spellcheck = false;
  keyInput.placeholder = "Typhoon API key · session only";
  keyInput.setAttribute("aria-label","Typhoon API key for this session only");
  keyInput.value = "";

  const useBtn = document.createElement("button");
  useBtn.id = "useTyphoonBtn";
  useBtn.textContent = "ใช้ Typhoon";
  useBtn.onclick = () => {
    const key = String(keyInput.value || "").trim();
    if (key.length < 12) {keyInput.setCustomValidity("ใส่ Typhoon API key ก่อน");keyInput.reportValidity();return;}
    keyInput.setCustomValidity("");
    sessionKey = key;
    keyInput.value = "";
    runtime.setProviderMode(`provider:${PROVIDER_ID}`);
    const select=document.getElementById("providerSelect");if(select)select.value=`provider:${PROVIDER_ID}`;
    updateHud();
  };

  const clearBtn = document.createElement("button");
  clearBtn.id = "clearTyphoonKeyBtn";
  clearBtn.textContent = "ล้าง Key";
  clearBtn.onclick = () => {sessionKey="";keyInput.value="";runtime.setProviderMode(PROVIDER_MODE.LOCAL);const select=document.getElementById("providerSelect");if(select)select.value=PROVIDER_MODE.LOCAL;updateHud();};

  endpointInput.insertAdjacentElement("afterend",clearBtn);
  endpointInput.insertAdjacentElement("afterend",useBtn);
  endpointInput.insertAdjacentElement("afterend",keyInput);

  const oldSnapshot = runtime.snapshot.bind(runtime);
  runtime.snapshot = function(){
    const snap = oldSnapshot();
    snap.provider.byok = provider.status();
    // Deliberately expose only a boolean. Never export the credential itself.
    snap.provider.byok.configured = provider.isConfigured();
    return snap;
  };

  window.AstraLifeTyphoonBYOK = Object.freeze({
    version:"p6.byok.1",
    providerId:PROVIDER_ID,
    model:MODEL,
    endpoint:ENDPOINT,
    hasKey:()=>provider.isConfigured(),
    setKey:key=>{sessionKey=String(key||"").trim();return provider.isConfigured()},
    clearKey:()=>{sessionKey="";return true},
    enable:()=>{if(!provider.isConfigured())throw new Error("Typhoon API key is not set");runtime.setProviderMode(`provider:${PROVIDER_ID}`);return runtime.decisionRouter.mode},
    status:()=>provider.status()
  });
})();

(() => {
  "use strict";

  const PROVIDER_ID = "typhoon-byok";
  const MODEL = "typhoon-v2.5-30b-a3b-instruct";
  const ENDPOINT = "https://api.opentyphoon.ai/v1/chat/completions";
  const MAX_CONCURRENT = 3;
  const MAX_CALLS_PER_MINUTE = 180;
  const MAX_RETRIES = 1;
  const MAX_API_MESSAGES = 44;
  const COMPACT_AT_HISTORY_MESSAGES = 36;
  const KEEP_RECENT_HISTORY_MESSAGES = 12;
  let sessionKey = "";

  const calls = [];
  const sessions = new Map();
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

  const SYSTEM_PROMPT = [
    "You are the decision engine for exactly ONE AstraLife agent.",
    "This conversation belongs only to that agent. Never merge identity, memories, plans, or observations with another agent.",
    "Use ONLY the current turn input plus prior messages in this same agent session. Never infer hidden world state.",
    "The current input contains the authoritative actionContract.allowedTypes; obey it exactly.",
    "Return one compact JSON object only. Do not reveal chain-of-thought.",
    "Include thought as ONE short natural first-person public thought for the player-facing bubble. It is not chain-of-thought.",
    "Do not write UI labels, telemetry, attitude tags, or strings like GOAL · ACTION · REASON inside thought.",
    "Return shape: {\"action\":{\"type\":\"WAIT\",\"payload\":{}},\"thought\":\"one natural public thought\",\"goal\":\"short goal\",\"reason\":\"short observable reason\",\"plan\":\"short plan\",\"confidence\":0.7,\"replanAfterTicks\":12}.",
    "Payloads: MOVE{x,y,speed?}; GATHER{resourceId,resourceType,carryType}; CONSUME{resource}; HEAL{targetAgentId}; SHARE{intent,facts,targetAgentId?,replyTo?,urgency?,text?}; DEPOSIT/REST/BUILD/WAIT use {}.",
    "Keep thought <= 140 chars, confidence 0..1 and replanAfterTicks 1..120."
  ].join("\n");

  function compactRequest(request){
    const copy = cloneJson(request);
    if (copy?.memory?.recentEpisodes?.length > 8) copy.memory.recentEpisodes = copy.memory.recentEpisodes.slice(-8);
    if (copy?.memory?.symbolicFacts?.length > 18) copy.memory.symbolicFacts = copy.memory.symbolicFacts.slice(0,18);
    if (copy?.observation?.messages?.length > 8) copy.observation.messages = copy.observation.messages.slice(-8);
    return copy;
  }

  function userTurnFor(request){
    return `Current authoritative turn input for Agent ${request.agent.id}:\n${JSON.stringify(compactRequest(request))}`;
  }

  function createSession(request){
    return {
      agentId:Number(request.agent.id),
      sessionId:String(request.sessionId),
      simulationId:String(request.simulation.id),
      history:[],
      recap:"",
      successfulTurns:0,
      rollovers:0,
      lastApiMessageCount:0,
      createdAt:Date.now(),
      lastUsedAt:Date.now()
    };
  }

  function getSession(request){
    const id=Number(request.agent.id);
    let session=sessions.get(id);
    if(!session || session.sessionId!==String(request.sessionId) || session.simulationId!==String(request.simulation.id)){
      session=createSession(request);
      sessions.set(id,session);
    }
    session.lastUsedAt=Date.now();
    return session;
  }

  function decisionLineFromAssistant(content){
    try{
      const parsed=JSON.parse(stripFence(content));
      const action=safeText(parsed?.action?.type||"",18);
      const thought=safeText(parsed?.thought||parsed?.publicThought||parsed?.reason||parsed?.goal||"",120).replace(/\s+/g," ").trim();
      if(!action&&!thought)return "";
      return `${action||"DECIDE"}${thought?`: ${thought}`:""}`;
    }catch{return ""}
  }

  function compactSession(session){
    if(session.history.length < COMPACT_AT_HISTORY_MESSAGES)return;
    const keep=session.history.slice(-KEEP_RECENT_HISTORY_MESSAGES);
    const older=session.history.slice(0,-KEEP_RECENT_HISTORY_MESSAGES);
    const lines=older.filter(m=>m.role==="assistant").map(m=>decisionLineFromAssistant(m.content)).filter(Boolean).slice(-14);
    const previous=session.recap?session.recap.replace(/^Earlier private session recap:\s*/i,"").trim():"";
    const combined=[previous,...lines].filter(Boolean).join(" | ");
    session.recap=`Earlier private session recap: ${combined.slice(-1500)}`;
    session.history=keep;
    session.rollovers++;
  }

  function buildMessages(request,session){
    compactSession(session);
    const userContent=userTurnFor(request);
    let messages=[{role:"system",content:SYSTEM_PROMPT}];
    if(session.recap)messages.push({role:"system",content:session.recap});
    messages.push(...session.history.map(m=>({role:m.role,content:m.content})));
    messages.push({role:"user",content:userContent});

    if(messages.length>MAX_API_MESSAGES){
      session.history=session.history.slice(-KEEP_RECENT_HISTORY_MESSAGES);
      session.rollovers++;
      messages=[{role:"system",content:SYSTEM_PROMPT}];
      if(session.recap)messages.push({role:"system",content:session.recap});
      messages.push(...session.history.map(m=>({role:m.role,content:m.content})));
      messages.push({role:"user",content:userContent});
    }
    if(messages.length>MAX_API_MESSAGES)throw new Error(`Agent session message cap exceeded (${messages.length}/${MAX_API_MESSAGES})`);
    session.lastApiMessageCount=messages.length;
    return {messages,userContent};
  }

  function rememberSuccessfulTurn(session,userContent,assistantContent){
    session.history.push({role:"user",content:userContent},{role:"assistant",content:String(assistantContent)});
    session.successfulTurns++;
    session.lastUsedAt=Date.now();
    compactSession(session);
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
    const thought = safeText(src.thought || src.publicThought || reason || plan || goal, 140);
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
        cognition:{goal,reason,plan,thought},
        thought,
        reason,confidence,replanAfterTicks
      },
      diagnostics:{engine:"opentyphoon-direct-byok",model:MODEL,keyPersistence:"memory-only",sessionIsolation:"per-agent"}
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
      const agentSession=getSession(request);
      const turn=buildMessages(request,agentSession);
      calls.push(Date.now()); stats.calls++; this.inFlight++;
      try {
        let lastError = null;
        for (let attempt=0; attempt<=MAX_RETRIES; attempt++) {
          try {
            const response = await fetch(ENDPOINT, {
              method:"POST",
              headers:{"authorization":`Bearer ${sessionKey}`,"content-type":"application/json","accept":"application/json"},
              body:JSON.stringify({model:MODEL,messages:turn.messages,temperature:.2,max_tokens:560,stream:false}),
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
            rememberSuccessfulTurn(agentSession,turn.userContent,content);
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
    status(){
      prune();
      return {
        configured:this.isConfigured(),model:MODEL,endpoint:ENDPOINT,inFlight:this.inFlight,callsLastMinute:calls.length,
        limits:{maxConcurrent:MAX_CONCURRENT,maxCallsPerMinute:MAX_CALLS_PER_MINUTE,maxRetries:MAX_RETRIES,maxApiMessages:MAX_API_MESSAGES,compactAtHistoryMessages:COMPACT_AT_HISTORY_MESSAGES,keepRecentHistoryMessages:KEEP_RECENT_HISTORY_MESSAGES},
        sessions:{count:sessions.size,totalTurns:[...sessions.values()].reduce((n,s)=>n+s.successfulTurns,0),totalRollovers:[...sessions.values()].reduce((n,s)=>n+s.rollovers,0)},
        stats:{...stats}
      };
    }
  }

  const provider = new TyphoonByokProvider();
  window.AstraColony.registerProvider(PROVIDER_ID,provider,{label:"Typhoon 2.5 · BYOK (independent Agents)",async:true,description:"Direct browser provider; one API key with isolated per-Agent LLM sessions; key stays only in page memory"});

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
    if(key!==sessionKey)sessions.clear();
    sessionKey = key;
    keyInput.value = "";
    runtime.setProviderMode(`provider:${PROVIDER_ID}`);
    const select=document.getElementById("providerSelect");if(select)select.value=`provider:${PROVIDER_ID}`;
    updateHud();
  };

  const clearBtn = document.createElement("button");
  clearBtn.id = "clearTyphoonKeyBtn";
  clearBtn.textContent = "ล้าง Key";
  clearBtn.onclick = () => {sessionKey="";sessions.clear();keyInput.value="";runtime.setProviderMode(PROVIDER_MODE.LOCAL);const select=document.getElementById("providerSelect");if(select)select.value=PROVIDER_MODE.LOCAL;updateHud();};

  endpointInput.insertAdjacentElement("afterend",clearBtn);
  endpointInput.insertAdjacentElement("afterend",useBtn);
  endpointInput.insertAdjacentElement("afterend",keyInput);

  const oldSnapshot = runtime.snapshot.bind(runtime);
  runtime.snapshot = function(){
    const snap = oldSnapshot();
    snap.provider.byok = provider.status();
    snap.provider.byok.configured = provider.isConfigured();
    return snap;
  };

  function sessionStats(agentId){
    const s=sessions.get(Number(agentId));
    if(!s)return null;
    return {agentId:s.agentId,sessionId:s.sessionId,simulationId:s.simulationId,historyMessages:s.history.length,hasRecap:!!s.recap,successfulTurns:s.successfulTurns,rollovers:s.rollovers,lastApiMessageCount:s.lastApiMessageCount,lastUsedAt:s.lastUsedAt};
  }

  window.AstraLifeTyphoonBYOK = Object.freeze({
    version:"p6.5-independent-agent-sessions",
    providerId:PROVIDER_ID,
    model:MODEL,
    endpoint:ENDPOINT,
    hasKey:()=>provider.isConfigured(),
    setKey:key=>{const next=String(key||"").trim();if(next!==sessionKey)sessions.clear();sessionKey=next;return provider.isConfigured()},
    clearKey:()=>{sessionKey="";sessions.clear();return true},
    enable:()=>{if(!provider.isConfigured())throw new Error("Typhoon API key is not set");runtime.setProviderMode(`provider:${PROVIDER_ID}`);return runtime.decisionRouter.mode},
    status:()=>provider.status(),
    sessionStats,
    sessionAgentIds:()=>[...sessions.keys()],
    clearSessions:()=>{sessions.clear();return true}
  });
})();

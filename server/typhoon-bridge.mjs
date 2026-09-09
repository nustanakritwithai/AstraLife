import http from "node:http";

const VERSION = "p6.0";
const PORT = Number(process.env.PORT || 8787);
const API_KEY = process.env.OPENTYPHOON_API_KEY || "";
const API_BASE = String(process.env.OPENTYPHOON_BASE_URL || "https://api.opentyphoon.ai/v1").replace(/\/$/, "");
const MODEL = process.env.OPENTYPHOON_MODEL || "typhoon-v2.5-30b-a3b-instruct";
const ALLOWED_ORIGINS = new Set(String(process.env.ASTRALIFE_ALLOWED_ORIGINS || "https://nustanakritwithai.github.io")
  .split(",").map(value => value.trim()).filter(Boolean));
const LIMITS = Object.freeze({
  maxConcurrent: Number(process.env.TYPHOON_MAX_CONCURRENT || 4),
  maxQueue: Number(process.env.TYPHOON_MAX_QUEUE || 64),
  maxCallsPerMinute: Number(process.env.TYPHOON_MAX_CALLS_PER_MINUTE || 160),
  maxTokensPerMinute: Number(process.env.TYPHOON_MAX_TOKENS_PER_MINUTE || 120000),
  maxInputTokens: Number(process.env.TYPHOON_MAX_INPUT_TOKENS || 12000),
  maxOutputTokens: Number(process.env.TYPHOON_MAX_OUTPUT_TOKENS || 420),
  timeoutMs: Number(process.env.TYPHOON_TIMEOUT_MS || 9000),
  retryLimit: Number(process.env.TYPHOON_RETRY_LIMIT || 2),
  sessionCap: Number(process.env.TYPHOON_SESSION_CAP || 256),
  responseBytes: 128000,
  requestBytes: 256000
});

const sessions = new Map();
const queue = [];
const callTimes = [];
const tokenEvents = [];
let active = 0;
let pumpTimer = null;

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const finite = value => Number.isFinite(Number(value));
const estimateTokens = value => Math.ceil(Buffer.byteLength(typeof value === "string" ? value : JSON.stringify(value), "utf8") / 4);
const text = value => String(value ?? "");
const retryableStatus = status => status === 429 || [500, 502, 503, 504].includes(status);

function pruneWindows(now=Date.now()){
  while(callTimes.length && now - callTimes[0] >= 60000) callTimes.shift();
  while(tokenEvents.length && now - tokenEvents[0].at >= 60000) tokenEvents.shift();
}
function tokenWindow(){ pruneWindows(); return tokenEvents.reduce((sum, item) => sum + item.tokens, 0); }
function retryDelay(attempt, response=null){
  const retryAfter = Number(response?.headers?.get?.("retry-after"));
  if(Number.isFinite(retryAfter) && retryAfter >= 0) return Math.min(5000, retryAfter * 1000);
  return Math.min(5000, 300 * (2 ** attempt) + Math.floor(Math.random() * 180));
}
function json(res, status, body, extraHeaders={}){
  const payload = JSON.stringify(body);
  res.writeHead(status, {"content-type":"application/json; charset=utf-8", "cache-control":"no-store", ...extraHeaders});
  res.end(payload);
}
function corsHeaders(req){
  const origin = text(req.headers.origin).trim();
  if(!origin) return {};
  if(ALLOWED_ORIGINS.has("*") || ALLOWED_ORIGINS.has(origin)){
    return {
      "access-control-allow-origin": ALLOWED_ORIGINS.has("*") ? "*" : origin,
      "vary":"Origin",
      "access-control-allow-headers":"content-type, x-astra-bridge-version",
      "access-control-allow-methods":"POST, OPTIONS"
    };
  }
  return null;
}
function assert(condition, message, status=400){
  if(!condition){ const error = new Error(message); error.status = status; throw error; }
}
function validateRequest(request){
  assert(request && typeof request === "object" && !Array.isArray(request), "request must be an object");
  assert(request.protocol === "astra-colony.decision-request.v1" || request.protocol === "astra.decision.v1" || text(request.protocol).includes("decision-request"), "decision request protocol mismatch");
  assert(request.simulation && request.agent && request.observation && request.memory && request.actionContract, "decision request is incomplete");
  const identity = request.identity;
  assert(identity && typeof identity === "object", "P6 identity envelope missing");
  for(const field of ["simulationId","runEpoch","agentId","sessionId","requestId","observationId","deadlineTick"]){
    assert(identity[field] !== undefined && identity[field] !== null && text(identity[field]).length > 0, `identity.${field} missing`);
  }
  assert(identity.simulationId === request.simulation.id, "identity simulation mismatch");
  assert(Number(identity.agentId) === Number(request.agent.id), "identity agent mismatch");
  assert(identity.sessionId === request.sessionId, "identity session mismatch");
  assert(identity.requestId === request.requestId, "identity request mismatch");
  assert(Number(identity.deadlineTick) >= Number(request.simulation.tick), "deadlineTick precedes request tick");
  const hint = request.simulation.providerHint;
  assert(hint === "typhoon" || hint === "remote", `unsupported providerHint: ${hint}`);
  assert(Array.isArray(request.actionContract.allowedTypes) && request.actionContract.allowedTypes.length > 0, "allowed action types missing");
  return identity;
}
function sessionKey(identity){ return `${identity.simulationId}|${identity.runEpoch}|${identity.sessionId}`; }
function getSession(identity){
  const key = sessionKey(identity);
  let session = sessions.get(key);
  if(!session){
    session = {key, simulationId:identity.simulationId, runEpoch:identity.runEpoch, sessionId:identity.sessionId, agentId:identity.agentId, createdAt:Date.now(), lastSeenAt:Date.now(), calls:0, responses:new Map()};
    sessions.set(key, session);
    while(sessions.size > LIMITS.sessionCap) sessions.delete(sessions.keys().next().value);
  }
  assert(Number(session.agentId) === Number(identity.agentId), "session reused by another agent", 409);
  session.lastSeenAt = Date.now();
  return session;
}
function providerView(request){
  const memory = request.memory || {};
  return {
    identity: request.identity,
    simulation: request.simulation,
    agent: request.agent,
    observation: request.observation,
    memory: {
      currentGoal: memory.currentGoal,
      goalReason: memory.goalReason,
      currentPlan: memory.currentPlan,
      beliefStock: memory.beliefStock,
      knownShelters: memory.knownShelters,
      failedActions: memory.failedActions,
      newFactKeys: Array.isArray(memory.newFactKeys) ? memory.newFactKeys.slice(0,8) : [],
      symbolicFacts: Array.isArray(memory.symbolicFacts) ? memory.symbolicFacts.slice(0,24) : [],
      recentEpisodes: Array.isArray(memory.recentEpisodes) ? memory.recentEpisodes.slice(-8) : [],
      social: memory.social || {}
    },
    actionContract: request.actionContract
  };
}
const SYSTEM_PROMPT = `You are the decision model for one isolated AstraLife agent.\nReturn ONLY one compact JSON object. Never reveal chain-of-thought. Use only the supplied observation, memory, beliefs, and action contract. Do not invent hidden world state. You may propose exactly one action, but the AstraLife validator and resolver are authoritative.\nRequired JSON shape:\n{"action":{"type":"WAIT","payload":{}},"goal":"short goal","reason":"brief observable reason","plan":"short next-step plan","confidence":0.7,"replanAfterTicks":24}\nThe action.type must be one of actionContract.allowedTypes. Keep reason concise and do not include private reasoning traces.`;
function extractJson(content){
  const raw = text(content).trim();
  try{ return JSON.parse(raw); }catch{}
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1];
  if(fenced){ try{ return JSON.parse(fenced.trim()); }catch{} }
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if(start >= 0 && end > start){ try{ return JSON.parse(raw.slice(start, end + 1)); }catch{} }
  throw new Error("Typhoon response did not contain valid JSON");
}
function normalizeModelDecision(request, modelDecision){
  assert(modelDecision && typeof modelDecision === "object" && !Array.isArray(modelDecision), "Typhoon decision must be an object", 502);
  const action = modelDecision.action && typeof modelDecision.action === "object" ? modelDecision.action : {type:"WAIT", payload:{}};
  const payload = action.payload && typeof action.payload === "object" && !Array.isArray(action.payload) ? action.payload : {};
  const confidence = finite(modelDecision.confidence) ? clamp(Number(modelDecision.confidence), 0, 1) : 0.65;
  const replanAfterTicks = finite(modelDecision.replanAfterTicks) ? clamp(Math.floor(Number(modelDecision.replanAfterTicks)), 1, 120) : 24;
  const reason = text(modelDecision.reason || "Typhoon decision").slice(0, 240);
  const goal = text(modelDecision.goal || request.memory?.currentGoal || "orient").slice(0, 80) || "orient";
  const plan = text(modelDecision.plan || action.type || "WAIT").slice(0, 220);
  return {action:{protocol:request.actionContract.protocol, type:text(action.type), payload}, goal, reason, plan, confidence, replanAfterTicks};
}
async function fetchTyphoon(request){
  assert(API_KEY, "OPENTYPHOON_API_KEY is not configured", 503);
  const view = providerView(request);
  const userContent = JSON.stringify(view);
  const estimatedInput = estimateTokens(userContent) + estimateTokens(SYSTEM_PROMPT);
  const requestInputCap = clamp(Number(request.providerBudget?.maxInputTokens || LIMITS.maxInputTokens), 256, LIMITS.maxInputTokens);
  assert(estimatedInput <= requestInputCap, `provider input token estimate ${estimatedInput} exceeds cap ${requestInputCap}`, 413);

  const outputCap = clamp(Number(request.providerBudget?.maxOutputTokens || LIMITS.maxOutputTokens), 64, LIMITS.maxOutputTokens);
  const timeoutMs = clamp(Number(request.providerBudget?.timeoutMs || LIMITS.timeoutMs), 500, LIMITS.timeoutMs);
  const retryLimit = clamp(Number(request.providerBudget?.retryLimit ?? LIMITS.retryLimit), 0, LIMITS.retryLimit);
  let lastError = null;

  for(let attempt=0; attempt<=retryLimit; attempt++){
    pruneWindows();
    assert(callTimes.length < LIMITS.maxCallsPerMinute, "bridge calls/minute budget exhausted", 429);
    assert(tokenWindow() + estimatedInput + outputCap <= LIMITS.maxTokensPerMinute, "bridge tokens/minute budget exhausted", 429);
    callTimes.push(Date.now());
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const started = Date.now();
    let response;
    try{
      response = await fetch(`${API_BASE}/chat/completions`, {
        method:"POST",
        headers:{"content-type":"application/json", "authorization":`Bearer ${API_KEY}`},
        body:JSON.stringify({
          model: MODEL,
          messages:[{role:"system",content:SYSTEM_PROMPT},{role:"user",content:userContent}],
          max_tokens: outputCap,
          temperature: 0.15,
          top_p: 0.9,
          stream: false
        }),
        signal:controller.signal
      });
      const raw = await response.text();
      if(raw.length > LIMITS.responseBytes) throw new Error("Typhoon response exceeded bridge byte limit");
      if(!response.ok){
        const error = new Error(`Typhoon HTTP ${response.status}: ${raw.slice(0,180)}`);
        error.status = response.status; error.response = response;
        throw error;
      }
      const upstream = JSON.parse(raw);
      const content = upstream?.choices?.[0]?.message?.content;
      const modelDecision = extractJson(content);
      const decision = normalizeModelDecision(request, modelDecision);
      const usage = upstream?.usage || {};
      const recordedTokens = Number(usage.total_tokens || (usage.prompt_tokens || estimatedInput) + (usage.completion_tokens || estimateTokens(content)));
      tokenEvents.push({at:Date.now(), tokens:Math.max(1, recordedTokens)});
      return {
        decision,
        diagnostics:{
          actualProvider:"opentyphoon",
          model: upstream?.model || MODEL,
          upstreamRequestId: upstream?.id || null,
          usage: {
            promptTokens:Number(usage.prompt_tokens || estimatedInput),
            completionTokens:Number(usage.completion_tokens || estimateTokens(content)),
            totalTokens:Math.max(1, recordedTokens)
          },
          latencyMs:Date.now()-started,
          retries:attempt,
          bridgeVersion:VERSION
        }
      };
    }catch(error){
      lastError = error instanceof Error ? error : new Error(text(error));
      const status = Number(lastError.status || 0);
      const retryable = lastError.name === "AbortError" || retryableStatus(status);
      if(retryable && attempt < retryLimit){ await sleep(retryDelay(attempt, lastError.response)); continue; }
      if(lastError.name === "AbortError"){ const timeout = new Error("Typhoon request timed out"); timeout.status = 504; throw timeout; }
      throw lastError;
    }finally{ clearTimeout(timer); }
  }
  throw lastError || new Error("Typhoon provider failed");
}
async function decide(request){
  const identity = validateRequest(request);
  const session = getSession(identity);
  const duplicate = session.responses.get(identity.requestId);
  if(duplicate) return duplicate;
  const {decision, diagnostics} = await fetchTyphoon(request);
  session.calls++;
  const response = {
    protocol:"astra-colony.decision-response.v1",
    requestId:request.requestId,
    agentId:request.agent.id,
    tick:request.simulation.tick,
    provider:request.simulation.providerHint,
    identity:{...identity},
    decision:{
      action:decision.action,
      cognition:{goal:decision.goal, reason:decision.reason, plan:decision.plan},
      reason:decision.reason,
      confidence:decision.confidence,
      replanAfterTicks:decision.replanAfterTicks
    },
    diagnostics:{...diagnostics, sessionCalls:session.calls}
  };
  session.responses.set(identity.requestId, response);
  while(session.responses.size > 16) session.responses.delete(session.responses.keys().next().value);
  return response;
}
function schedulePump(ms){
  if(pumpTimer) return;
  pumpTimer = setTimeout(() => { pumpTimer = null; pump(); }, Math.max(10, ms));
}
function pump(){
  pruneWindows();
  while(active < LIMITS.maxConcurrent && queue.length && callTimes.length < LIMITS.maxCallsPerMinute){
    const job = queue.shift(); active++;
    decide(job.request).then(job.resolve, job.reject).finally(() => { active--; pump(); });
  }
  if(queue.length && callTimes.length >= LIMITS.maxCallsPerMinute){
    schedulePump(Math.max(20, 60000 - (Date.now() - callTimes[0]) + 10));
  }
}
function enqueue(request){
  if(queue.length >= LIMITS.maxQueue){ const error = new Error("bridge queue budget exhausted"); error.status = 429; return Promise.reject(error); }
  return new Promise((resolve, reject) => { queue.push({request, resolve, reject}); pump(); });
}

const server = http.createServer((req, res) => {
  const cors = corsHeaders(req);
  if(cors === null){ json(res, 403, {error:"origin not allowed"}); return; }
  for(const [key, value] of Object.entries(cors || {})) res.setHeader(key, value);
  if(req.method === "OPTIONS"){ res.writeHead(204); res.end(); return; }
  if(req.method === "GET" && req.url === "/health"){
    json(res, 200, {ok:true, bridgeVersion:VERSION, provider:"opentyphoon", model:MODEL, configured:!!API_KEY, active, queued:queue.length, callsInWindow:callTimes.length, tokensInWindow:tokenWindow()});
    return;
  }
  if(req.method !== "POST" || req.url !== "/decide"){ json(res, 404, {error:"not found"}); return; }

  let body = "";
  req.setEncoding("utf8");
  req.on("data", chunk => {
    body += chunk;
    if(Buffer.byteLength(body, "utf8") > LIMITS.requestBytes) req.destroy(new Error("request too large"));
  });
  req.on("end", async () => {
    try{
      const request = JSON.parse(body);
      const response = await enqueue(request);
      json(res, 200, response);
    }catch(error){
      const status = clamp(Number(error?.status || 500), 400, 599);
      const headers = status === 429 ? {"retry-after":"1"} : {};
      json(res, status, {error:text(error?.message || error).slice(0,240), bridgeVersion:VERSION}, headers);
    }
  });
});

server.listen(PORT, () => {
  console.log(`AstraLife Typhoon bridge ${VERSION} listening on :${PORT}`);
  console.log(`model=${MODEL} keyConfigured=${API_KEY ? "yes" : "no"} allowedOrigins=${[...ALLOWED_ORIGINS].join(",")}`);
});

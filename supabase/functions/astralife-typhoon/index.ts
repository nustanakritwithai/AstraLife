import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const TYPHOON_URL = "https://api.opentyphoon.ai/v1/chat/completions";
const DEFAULT_MODEL = "typhoon-v2.5-30b-a3b-instruct";
const MAX_BODY_BYTES = 180_000;
const ALLOWED_ORIGINS = new Set([
  "https://nustanakritwithai.github.io",
  "http://localhost:8000",
  "http://127.0.0.1:8000",
  "null"
]);

const corsHeaders = (origin: string | null) => ({
  "access-control-allow-origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://nustanakritwithai.github.io",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "vary": "Origin"
});

const json = (status: number, body: unknown, origin: string | null) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders(origin), "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
});

const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));
const safeText = (value: unknown, max: number) => String(value ?? "").slice(0, max);

function stripCodeFence(text: string) {
  const trimmed = text.trim();
  if (!trimmed.startsWith("```")) return trimmed;
  return trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
}

function validIdentity(identity: any) {
  return identity &&
    typeof identity.simulationId === "string" &&
    Number.isInteger(identity.runEpoch) &&
    Number.isInteger(identity.agentId) &&
    typeof identity.sessionId === "string" &&
    typeof identity.requestId === "string" &&
    typeof identity.observationId === "string" &&
    Number.isInteger(identity.deadlineTick);
}

function compactRequest(request: any) {
  const copy = structuredClone(request);
  if (copy?.memory?.recentEpisodes?.length > 8) copy.memory.recentEpisodes = copy.memory.recentEpisodes.slice(-8);
  if (copy?.memory?.symbolicFacts?.length > 18) copy.memory.symbolicFacts = copy.memory.symbolicFacts.slice(0, 18);
  if (copy?.observation?.messages?.length > 8) copy.observation.messages = copy.observation.messages.slice(-8);
  return copy;
}

function promptFor(request: any) {
  const allowed = Array.isArray(request?.actionContract?.allowedTypes) ? request.actionContract.allowedTypes : ["WAIT"];
  return [
    "You are the decision engine for one AstraLife agent.",
    "Use ONLY the supplied observation, memory, beliefs and action contract. Never assume hidden world state.",
    "Choose exactly ONE allowed action. Do not write chain-of-thought. Return compact JSON only.",
    `Allowed action types: ${allowed.join(", ")}`,
    "Return shape:",
    '{"action":{"type":"WAIT","payload":{}},"goal":"short goal","reason":"short observable reason","plan":"short next-step plan","confidence":0.0,"replanAfterTicks":12}',
    "Payload requirements: MOVE{x,y,speed?}; GATHER{resourceId,resourceType,carryType}; CONSUME{resource}; HEAL{targetAgentId}; SHARE{intent,facts,targetAgentId?,replyTo?,urgency?,text?}; DEPOSIT/REST/BUILD/WAIT use {}.",
    "Keep confidence between 0 and 1 and replanAfterTicks between 1 and 120.",
    "Decision request follows:",
    JSON.stringify(compactRequest(request))
  ].join("\n");
}

function normaliseModelDecision(raw: any, request: any) {
  const allowed = new Set(Array.isArray(request?.actionContract?.allowedTypes) ? request.actionContract.allowedTypes : ["WAIT"]);
  const candidate = raw && typeof raw === "object" ? raw : {};
  const action = candidate.action && typeof candidate.action === "object" ? candidate.action : { type: "WAIT", payload: {} };
  const type = allowed.has(action.type) ? action.type : "WAIT";
  const payload = action.payload && typeof action.payload === "object" && !Array.isArray(action.payload) ? action.payload : {};
  return {
    action: { type, payload: type === "WAIT" ? {} : payload },
    goal: safeText(candidate.goal || request?.memory?.currentGoal || "orient", 80) || "orient",
    reason: safeText(candidate.reason || "Typhoon selected a bounded action from observable state", 180),
    plan: safeText(candidate.plan || type, 220),
    confidence: clamp(Number(candidate.confidence) || 0.5, 0, 1),
    replanAfterTicks: clamp(Math.floor(Number(candidate.replanAfterTicks) || 18), 1, 120)
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return json(405, { error: "POST required" }, origin);
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json(403, { error: "origin not allowed" }, origin);

  const contentLength = Number(req.headers.get("content-length") || 0);
  if (contentLength > MAX_BODY_BYTES) return json(413, { error: "request too large" }, origin);

  let body: any;
  try {
    const text = await req.text();
    if (text.length > MAX_BODY_BYTES) return json(413, { error: "request too large" }, origin);
    body = JSON.parse(text);
  } catch {
    return json(400, { error: "invalid JSON" }, origin);
  }

  if (body?.protocol !== "astralife.provider-request.p6") return json(400, { error: "P6 protocol mismatch" }, origin);
  if (!validIdentity(body.identity)) return json(400, { error: "invalid P6 identity envelope" }, origin);
  const request = body.request;
  if (!request || request.protocol !== "astra-colony.decision-request.v1") return json(400, { error: "decision request protocol mismatch" }, origin);
  if (request.requestId !== body.identity.requestId || request.sessionId !== body.identity.sessionId || request.agent?.id !== body.identity.agentId || request.simulation?.id !== body.identity.simulationId) {
    return json(400, { error: "identity/request mismatch" }, origin);
  }

  const apiKey = Deno.env.get("TYPHOON_API_KEY");
  if (!apiKey) return json(503, { error: "TYPHOON_API_KEY secret is not configured" }, origin);
  const model = Deno.env.get("TYPHOON_MODEL") || DEFAULT_MODEL;

  let upstream: Response;
  try {
    upstream = await fetch(TYPHOON_URL, {
      method: "POST",
      headers: { "authorization": `Bearer ${apiKey}`, "content-type": "application/json", "accept": "application/json" },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: "Return only the requested compact JSON decision. Never expose hidden chain-of-thought." },
          { role: "user", content: promptFor(request) }
        ],
        temperature: 0.2,
        max_tokens: 520,
        stream: false
      })
    });
  } catch (error) {
    return json(502, { error: `Typhoon network error: ${safeText((error as Error)?.message, 160)}` }, origin);
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    const status = upstream.status === 429 ? 429 : 502;
    return json(status, { error: `Typhoon HTTP ${upstream.status}`, detail: safeText(upstreamText, 300) }, origin);
  }

  let completion: any;
  try { completion = JSON.parse(upstreamText); }
  catch { return json(502, { error: "Typhoon returned invalid API JSON" }, origin); }

  const content = completion?.choices?.[0]?.message?.content;
  if (typeof content !== "string") return json(502, { error: "Typhoon response content missing" }, origin);

  let modelDecision: any;
  try { modelDecision = JSON.parse(stripCodeFence(content)); }
  catch { return json(502, { error: "Typhoon decision was not valid JSON", detail: safeText(content, 300) }, origin); }

  const decision = normaliseModelDecision(modelDecision, request);
  const response = {
    protocol: "astra-colony.decision-response.v1",
    requestId: request.requestId,
    agentId: request.agent.id,
    tick: request.simulation.tick,
    provider: "typhoon",
    decision: {
      action: { protocol: "astra-colony.action.v1", type: decision.action.type, payload: decision.action.payload },
      cognition: { goal: decision.goal, reason: decision.reason, plan: decision.plan },
      reason: decision.reason,
      confidence: decision.confidence,
      replanAfterTicks: decision.replanAfterTicks
    },
    diagnostics: { bridge: "supabase-edge", model }
  };

  return json(200, {
    protocol: "astralife.provider-response.p6",
    identity: body.identity,
    providerModel: model,
    usage: completion?.usage || null,
    response
  }, origin);
});

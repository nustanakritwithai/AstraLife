import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const TYPHOON_URL = "https://api.opentyphoon.ai/v1/chat/completions";
const DEFAULT_MODEL = "typhoon-v2.5-30b-a3b-instruct";
const MAX_BODY_BYTES = 650_000;
const MAX_AGENTS = 160;
const ALLOWED_ORIGINS = new Set([
  "https://nustanakritwithai.github.io",
  "http://localhost:8000",
  "http://127.0.0.1:8000",
  "null"
]);

const corsHeaders = (origin: string | null) => ({
  "access-control-allow-origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://nustanakritwithai.github.io",
  "access-control-allow-headers": "content-type, x-typhoon-key",
  "access-control-allow-methods": "POST, OPTIONS",
  "vary": "Origin"
});

const json = (status: number, body: unknown, origin: string | null) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders(origin), "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
});

const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));
const safeText = (value: unknown, max: number) => String(value ?? "").replace(/\s+/g, " ").trim().slice(0, max);

function stripCodeFence(text: string) {
  const trimmed = text.trim();
  if (!trimmed.startsWith("```")) return trimmed;
  return trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
}

function validIdentity(identity: any) {
  return identity &&
    typeof identity.simulationId === "string" &&
    Number.isInteger(identity.runEpoch) &&
    Number.isInteger(identity.tick) &&
    typeof identity.snapshotId === "string" &&
    Number.isInteger(identity.deadlineTick);
}

function promptFor(body: any) {
  return [
    "You are the World Snapshot Brain for AstraLife.",
    "You receive one authoritative world snapshot containing many agents.",
    "Return exactly ONE compact JSON object and no markdown or chain-of-thought.",
    "Choose one bounded action for EVERY agent using only that agent's supplied observation, memory and allowedTypes.",
    "Never invent hidden world state. Never mutate world state directly.",
    "Keep decisions terse. thought <= 80 chars, goal <= 40, reason <= 90, plan <= 100.",
    "Return shape:",
    '{"decisions":[{"agentId":1,"requestId":"...","action":{"type":"WAIT","payload":{}},"thought":"short public thought","goal":"short goal","reason":"observable reason","plan":"short plan","confidence":0.7,"replanAfterTicks":12}]}',
    "Payloads: MOVE{x,y,speed?}; GATHER{resourceId,resourceType,carryType}; CONSUME{resource}; HEAL{targetAgentId}; SHARE{intent,facts,targetAgentId?,replyTo?,urgency?,text?}; DEPOSIT/REST/BUILD/WAIT use {}.",
    "Snapshot follows:",
    JSON.stringify({ identity: body.identity, world: body.world, agents: body.agents })
  ].join("\n");
}

function normalizeDecision(raw: any, agent: any) {
  const allowed = new Set(Array.isArray(agent?.actionContract?.allowedTypes) ? agent.actionContract.allowedTypes : ["WAIT"]);
  const candidate = raw && typeof raw === "object" ? raw : {};
  const action = candidate.action && typeof candidate.action === "object" ? candidate.action : { type: "WAIT", payload: {} };
  const type = allowed.has(action.type) ? action.type : "WAIT";
  const payload = action.payload && typeof action.payload === "object" && !Array.isArray(action.payload) ? action.payload : {};
  return {
    agentId: Number(agent.agentId),
    requestId: String(agent.requestId),
    action: { type, payload: type === "WAIT" ? {} : payload },
    thought: safeText(candidate.thought || candidate.reason || "", 80),
    goal: safeText(candidate.goal || agent?.memory?.currentGoal || "orient", 40) || "orient",
    reason: safeText(candidate.reason || "world snapshot decision", 90),
    plan: safeText(candidate.plan || type, 100),
    confidence: clamp(Number(candidate.confidence) || 0.55, 0, 1),
    replanAfterTicks: clamp(Math.floor(Number(candidate.replanAfterTicks) || 12), 2, 120)
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return json(405, { error: "POST required" }, origin);
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json(403, { error: "origin not allowed" }, origin);

  const typhoonKey = String(req.headers.get("x-typhoon-key") || "").trim();
  if (typhoonKey.length < 12) return json(401, { error: "x-typhoon-key missing or invalid" }, origin);

  const contentLength = Number(req.headers.get("content-length") || 0);
  if (contentLength > MAX_BODY_BYTES) return json(413, { error: "snapshot request too large" }, origin);

  let body: any;
  try {
    const text = await req.text();
    if (text.length > MAX_BODY_BYTES) return json(413, { error: "snapshot request too large" }, origin);
    body = JSON.parse(text);
  } catch {
    return json(400, { error: "invalid JSON" }, origin);
  }

  if (body?.protocol !== "astralife.world-snapshot-request.p610") return json(400, { error: "P6.10 protocol mismatch" }, origin);
  if (!validIdentity(body.identity)) return json(400, { error: "invalid P6.10 identity" }, origin);
  if (!Array.isArray(body.agents) || body.agents.length < 1 || body.agents.length > MAX_AGENTS) return json(400, { error: "invalid agents batch" }, origin);

  const seen = new Set<number>();
  for (const agent of body.agents) {
    const id = Number(agent?.agentId);
    if (!Number.isInteger(id) || id < 1 || seen.has(id) || typeof agent?.requestId !== "string") return json(400, { error: "invalid/duplicate agent entry" }, origin);
    seen.add(id);
  }

  const model = Deno.env.get("TYPHOON_MODEL") || DEFAULT_MODEL;
  let upstream: Response;
  try {
    upstream = await fetch(TYPHOON_URL, {
      method: "POST",
      headers: { "authorization": `Bearer ${typhoonKey}`, "content-type": "application/json", "accept": "application/json" },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: "Return only compact JSON decisions for every AstraLife agent in the supplied snapshot. Never expose hidden chain-of-thought." },
          { role: "user", content: promptFor(body) }
        ],
        temperature: 0.2,
        max_tokens: 5000,
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

  let parsed: any;
  try { parsed = JSON.parse(stripCodeFence(content)); }
  catch { return json(502, { error: "Typhoon snapshot decision was not valid JSON", detail: safeText(content, 300) }, origin); }

  const rows = Array.isArray(parsed?.decisions) ? parsed.decisions : [];
  const byAgent = new Map<number, any>();
  for (const row of rows) {
    const id = Number(row?.agentId);
    if (Number.isInteger(id) && !byAgent.has(id)) byAgent.set(id, row);
  }

  const decisions = body.agents.map((agent: any) => normalizeDecision(byAgent.get(Number(agent.agentId)), agent));

  return json(200, {
    protocol: "astralife.world-snapshot-response.p610",
    identity: body.identity,
    providerModel: completion?.model || model,
    usage: completion?.usage || null,
    decisions
  }, origin);
});

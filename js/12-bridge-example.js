const NODE_BRIDGE_EXAMPLE=`import http from "node:http";

const sessions = new Map();
const PORT = 8787;

function decide(request) {
  const session = sessions.get(request.sessionId) || { calls: 0 };
  session.calls++;
  sessions.set(request.sessionId, session);

  // Replace this deterministic policy with your Astra provider call.
  // Keep one provider-side state/session per request.sessionId.
  const o = request.observation;
  let action = { protocol: "astra-colony.action.v1", type: "WAIT", payload: {} };
  let goal = request.memory.currentGoal || "observe";
  let reason = "bridge demonstration";

  if (o.self.thirst > 82 && o.camp.visible && o.camp.stock.water >= 1) {
    goal = "drink"; reason = "critical thirst";
    action = { protocol: "astra-colony.action.v1", type: "CONSUME", payload: { resource: "water" } };
  } else if (o.self.hunger > 84 && o.camp.visible && o.camp.stock.food >= 1) {
    goal = "eat"; reason = "critical hunger";
    action = { protocol: "astra-colony.action.v1", type: "CONSUME", payload: { resource: "food" } };
  }

  return {
    protocol: "astra-colony.decision-response.v1",
    requestId: request.requestId,
    agentId: request.agent.id,
    tick: request.simulation.tick,
    provider: "remote",
    decision: {
      action,
      cognition: { goal, reason, plan: action.type },
      reason,
      confidence: 0.75,
      replanAfterTicks: 24
    },
    diagnostics: { sessionCalls: session.calls }
  };
}

http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "content-type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") return res.end();
  if (req.method !== "POST" || req.url !== "/decide") {
    res.writeHead(404).end("Not found"); return;
  }
  let body = "";
  req.on("data", chunk => {
    body += chunk;
    if (body.length > 256_000) req.destroy();
  });
  req.on("end", () => {
    try {
      const request = JSON.parse(body);
      if (request.protocol !== "astra-colony.decision-request.v1") throw new Error("protocol mismatch");
      const response = decide(request);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(response));
    } catch (error) {
      res.writeHead(400, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: error.message }));
    }
  });
}).listen(PORT, () => console.log(\`ASTRA bridge: http://localhost:\${PORT}/decide\`));`;

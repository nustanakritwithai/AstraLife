(() => {
  "use strict";

  const VERSION = "p6.0";
  const DEFAULT_LIMITS = Object.freeze({
    maxConcurrent: 4,
    maxQueue: 48,
    maxCallsPerMinute: 160,
    requestTimeoutMs: 9000,
    retryLimit: 2,
    retryBaseMs: 280,
    deadlineTicks: 8,
    maxOutputTokens: 420,
    maxInputTokens: 12000,
    laneCount: 6
  });

  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const clampInt = (value, min, max, fallback) => {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback;
  };
  const p6Provider = hint => hint === "typhoon";
  const identityKey = identity => identity ? `${identity.simulationId}|${identity.runEpoch}|${identity.sessionId}|${identity.requestId}` : "";
  const observationIdFor = request => `obs:${request.simulation.id}:${request.simulation.tick}:${request.agent.id}`;

  const oldRequestBuild = DecisionRequestFactory.prototype.build;
  DecisionRequestFactory.prototype.build = function(state, agent, observation, providerHint){
    const base = oldRequestBuild.call(this, state, agent, observation, providerHint);
    const request = cloneJson(base);
    const runEpoch = Number(runtime?.decisionRouter?.epoch || 0);
    request.identity = {
      simulationId: base.simulation.id,
      runEpoch,
      agentId: base.agent.id,
      sessionId: base.sessionId,
      requestId: base.requestId,
      observationId: observationIdFor(base),
      deadlineTick: base.simulation.tick + DEFAULT_LIMITS.deadlineTicks
    };
    request.providerBudget = {
      maxOutputTokens: DEFAULT_LIMITS.maxOutputTokens,
      maxInputTokens: DEFAULT_LIMITS.maxInputTokens,
      timeoutMs: DEFAULT_LIMITS.requestTimeoutMs,
      retryLimit: DEFAULT_LIMITS.retryLimit
    };
    return deepFreeze(request);
  };

  const oldRequestSchema = DecisionRequestFactory.prototype.schema;
  DecisionRequestFactory.prototype.schema = function(){
    const schema = cloneJson(oldRequestSchema.call(this));
    schema.required = [...new Set([...(schema.required || []), "identity", "providerBudget"])];
    schema.properties = schema.properties || {};
    schema.properties.identity = {
      type: "object", additionalProperties: false,
      required: ["simulationId","runEpoch","agentId","sessionId","requestId","observationId","deadlineTick"],
      properties: {
        simulationId:{type:"string"}, runEpoch:{type:"integer",minimum:1}, agentId:{type:"integer",minimum:1},
        sessionId:{type:"string"}, requestId:{type:"string"}, observationId:{type:"string"}, deadlineTick:{type:"integer",minimum:0}
      }
    };
    schema.properties.providerBudget = {
      type:"object", additionalProperties:false,
      required:["maxOutputTokens","maxInputTokens","timeoutMs","retryLimit"],
      properties:{
        maxOutputTokens:{type:"integer",minimum:1}, maxInputTokens:{type:"integer",minimum:1},
        timeoutMs:{type:"integer",minimum:100}, retryLimit:{type:"integer",minimum:0,maximum:4}
      }
    };
    return schema;
  };

  class P6HttpProvider {
    constructor(endpointGetter, overrides={}){
      this.id = "typhoon";
      this.endpointGetter = endpointGetter;
      this.limits = {...DEFAULT_LIMITS, ...overrides};
      this.active = 0;
      this.queue = [];
      this.callTimes = [];
      this.pumpTimer = null;
      this.stats = {started:0, completed:0, retries:0, rateLimited:0, timedOut:0, queueRejected:0, httpErrors:0};
    }
    isConfigured(){ return !!String(this.endpointGetter() || "").trim(); }
    snapshot(){ return {...this.stats, active:this.active, queued:this.queue.length, callsInWindow:this.callsInWindow()}; }
    callsInWindow(){ this.pruneCalls(); return this.callTimes.length; }
    pruneCalls(now=Date.now()){ while(this.callTimes.length && now - this.callTimes[0] >= 60000) this.callTimes.shift(); }
    retryDelay(attempt, response=null){
      const retryAfter = Number(response?.headers?.get?.("retry-after"));
      if(Number.isFinite(retryAfter) && retryAfter >= 0) return Math.min(5000, retryAfter * 1000);
      const base = this.limits.retryBaseMs * (2 ** attempt);
      return Math.min(5000, base + Math.floor(Math.random() * Math.max(20, this.limits.retryBaseMs)));
    }
    decide(request){
      if(!this.isConfigured()) return Promise.reject(new Error("Typhoon secure bridge endpoint is empty"));
      if(!request?.identity) return Promise.reject(new Error("P6 identity envelope missing"));
      if(this.queue.length >= this.limits.maxQueue){
        this.stats.queueRejected++;
        return Promise.reject(new Error("P6 provider queue budget exhausted"));
      }
      return new Promise((resolve, reject) => {
        this.queue.push({request, resolve, reject, enqueuedAt:performance.now()});
        this.pump();
      });
    }
    schedulePump(ms){
      if(this.pumpTimer) return;
      this.pumpTimer = setTimeout(() => { this.pumpTimer = null; this.pump(); }, Math.max(10, ms));
    }
    pump(){
      this.pruneCalls();
      while(this.active < this.limits.maxConcurrent && this.queue.length && this.callTimes.length < this.limits.maxCallsPerMinute){
        const job = this.queue.shift();
        this.active++; this.callTimes.push(Date.now()); this.stats.started++;
        this.run(job.request).then(value => { this.stats.completed++; job.resolve(value); }, job.reject)
          .finally(() => { this.active--; this.pump(); });
      }
      if(this.queue.length && this.callTimes.length >= this.limits.maxCallsPerMinute){
        const wait = Math.max(20, 60000 - (Date.now() - this.callTimes[0]) + 5);
        this.schedulePump(wait);
      }
    }
    async run(request){
      const retryLimit = clampInt(request?.providerBudget?.retryLimit, 0, 4, this.limits.retryLimit);
      let lastError = null;
      for(let attempt=0; attempt<=retryLimit; attempt++){
        try{
          const result = await this.postOnce(request);
          if(result.retryable && attempt < retryLimit){
            this.stats.retries++;
            if(result.status === 429) this.stats.rateLimited++;
            await sleep(this.retryDelay(attempt, result.response));
            continue;
          }
          if(!result.ok) throw new Error(`provider HTTP ${result.status}: ${String(result.text || "").slice(0,180)}`);
          return result.data;
        }catch(error){
          lastError = error instanceof Error ? error : new Error(String(error));
          const retryableNetwork = lastError.name === "AbortError" || /network|fetch|timeout/i.test(lastError.message);
          if(lastError.name === "AbortError") this.stats.timedOut++;
          if(retryableNetwork && attempt < retryLimit){ this.stats.retries++; await sleep(this.retryDelay(attempt)); continue; }
          throw lastError;
        }
      }
      throw lastError || new Error("P6 provider failed");
    }
    async postOnce(request){
      const endpoint = String(this.endpointGetter() || "").trim();
      const timeoutMs = clampInt(request?.providerBudget?.timeoutMs, 100, this.limits.requestTimeoutMs, this.limits.requestTimeoutMs);
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try{
        const response = await fetch(endpoint, {
          method:"POST",
          headers:{"content-type":"application/json","accept":"application/json","x-astra-bridge-version":VERSION},
          body:JSON.stringify(request), signal:controller.signal, credentials:"omit", cache:"no-store", referrerPolicy:"no-referrer"
        });
        const text = await response.text();
        if(text.length > CONFIG.maxRemoteResponseBytes) throw new Error(`provider response exceeds ${CONFIG.maxRemoteResponseBytes} bytes`);
        const retryable = response.status === 429 || [500,502,503,504].includes(response.status);
        if(!response.ok){ this.stats.httpErrors++; return {ok:false,retryable,status:response.status,text,response}; }
        let data;
        try{ data = JSON.parse(text); }catch(error){ throw new Error(`provider returned invalid JSON: ${error.message}`); }
        return {ok:true,retryable:false,status:response.status,text,data,response};
      } finally { clearTimeout(timer); }
    }
  }

  const oldValidate = ActionContractValidator.prototype.validate;
  ActionContractValidator.prototype.validate = function(response, request, state){
    const base = oldValidate.call(this, response, request, state);
    if(!p6Provider(request?.simulation?.providerHint)) return base;
    const errors = [];
    const expected = request?.identity;
    const actual = response?.identity;
    const need = (ok, message) => { if(!ok) errors.push(message); };
    need(!!expected, "P6 request identity missing");
    need(!!actual && typeof actual === "object", "P6 response identity missing");
    if(expected && actual && typeof actual === "object"){
      for(const field of ["simulationId","runEpoch","agentId","sessionId","requestId","observationId","deadlineTick"]){
        need(actual[field] === expected[field], `P6 identity mismatch: ${field}`);
      }
      need(state.tick <= expected.deadlineTick, "P6 response exceeded deadlineTick");
    }
    if(!base.ok) errors.unshift(...base.errors);
    if(errors.length) return {ok:false, errors:[...new Set(errors)].slice(0,24)};
    return base;
  };

  const oldReset = DecisionRouter.prototype.reset;
  DecisionRouter.prototype.reset = function(...args){
    const out = oldReset.apply(this, args);
    this._p6Accepted = new Map();
    return out;
  };

  const oldSelectProvider = DecisionRouter.prototype.selectProvider;
  DecisionRouter.prototype.selectProvider = function(agent, observation){
    if(this.mode === "provider:typhoon"){
      const critical = observation.self.hp < 42 || observation.self.hunger > 82 || observation.self.thirst > 80 || (agent.runtime.lastOutcome && !agent.runtime.lastOutcome.ok);
      const deliberate = critical || agent.mind.goal === "orient" || agent.mind.replanAtTick <= observation.tick || agent.mind.failedActions > 2;
      if(!deliberate) return "local";
      const lane = Math.abs((Number(agent.id) + Number(observation.tick)) % DEFAULT_LIMITS.laneCount);
      return critical || lane === 0 ? "typhoon" : "local";
    }
    return oldSelectProvider.call(this, agent, observation);
  };

  const oldApplyAccepted = DecisionRouter.prototype.applyAccepted;
  DecisionRouter.prototype.applyAccepted = function(state, task, normalized, queue, isFallback=false){
    const request = task?.request;
    const providerHint = request?.simulation?.providerHint;
    if(p6Provider(providerHint) && !isFallback){
      this._p6Accepted = this._p6Accepted || new Map();
      const key = identityKey(request.identity);
      if(key && this._p6Accepted.has(key)){
        this.metrics.invalid++;
        this.count(normalized.provider || providerHint, "invalid");
        task.agent.runtime.lastValidation = {ok:false, errors:["duplicate P6 provider response rejected"], tick:state.tick, provider:normalized.provider || providerHint};
        this.memory.trace(task.agent, "VALIDATE", `REJECT · duplicate P6 response ${request.requestId}`);
        this.internalWait(state, task, queue, "duplicate P6 provider response rejected");
        return;
      }
      if(key){
        this._p6Accepted.set(key, state.tick);
        if(this._p6Accepted.size > 2048) this._p6Accepted.delete(this._p6Accepted.keys().next().value);
      }
    }
    const out = oldApplyAccepted.call(this, state, task, normalized, queue, isFallback);
    const diagnostics = normalized?.raw?.diagnostics;
    if(p6Provider(providerHint) && diagnostics && task?.agent?.runtime){
      task.agent.runtime.providerActual = String(diagnostics.actualProvider || normalized.provider || providerHint).slice(0,64);
      task.agent.runtime.providerModel = String(diagnostics.model || "unknown").slice(0,96);
      task.agent.runtime.providerUsage = cloneJson(diagnostics.usage || null);
      task.agent.runtime.providerBridgeVersion = String(diagnostics.bridgeVersion || VERSION).slice(0,32);
    }
    return out;
  };

  const typhoonAdapter = new P6HttpProvider(() => runtime.providerEndpoint);
  runtime.registry.register("typhoon", typhoonAdapter, {
    label:"Typhoon 2.5 · secure bridge", kind:"custom", async:true,
    description:"OpenTyphoon via a server-side credential bridge; no API key is stored in the browser."
  });
  if(typeof refreshProviderOptions === "function") refreshProviderOptions();

  window.AstraLifeP6 = Object.freeze({
    version: VERSION,
    limits: DEFAULT_LIMITS,
    providerId: "typhoon",
    getStats: () => typhoonAdapter.snapshot(),
    identityFor: agentId => {
      const agent = runtime.state.agentById.get(Number(agentId));
      return cloneJson(agent?.runtime?.lastDecisionRequest?.identity || null);
    },
    providerInfo: agentId => {
      const agent = runtime.state.agentById.get(Number(agentId));
      return agent ? {actualProvider:agent.runtime.providerActual || null, model:agent.runtime.providerModel || null, usage:cloneJson(agent.runtime.providerUsage || null)} : null;
    },
    createTestAdapter: (endpointGetter, overrides={}) => new P6HttpProvider(endpointGetter, overrides)
  });
})();

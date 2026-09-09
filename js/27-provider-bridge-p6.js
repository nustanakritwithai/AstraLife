(() => {
  "use strict";

  const VERSION = "p6.0";
  const DEFAULT_ENDPOINT = "https://dufgcgjhcgiefpdjxewp.supabase.co/functions/v1/astralife-typhoon";
  const LIMITS = Object.freeze({
    maxConcurrent: 3,
    maxCallsPerMinute: 120,
    maxEstimatedTokensPerMinute: 45000,
    maxInputTokensPerCall: 12000,
    maxRetries: 1,
    retryDelayCapMs: 1500
  });

  const runtimeRef = () => runtime;
  const estimateTokens = value => Math.ceil(JSON.stringify(value).length / 4);
  const same = (a, b) => String(a ?? "") === String(b ?? "");
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

  class TyphoonP6Provider {
    constructor(endpointGetter, runtimeGetter) {
      this.id = "typhoon";
      this.endpointGetter = endpointGetter;
      this.runtimeGetter = runtimeGetter;
      this.inFlight = 0;
      this.calls = [];
      this.tokenReservations = [];
      this.stats = {
        calls: 0, successes: 0, rejectedEnvelopes: 0, timeouts: 0,
        rateLimited: 0, retries: 0, budgetRejected: 0, providerErrors: 0,
        estimatedInputTokens: 0, actualTokens: 0, lastModel: null, lastError: null
      };
    }

    isConfigured() {
      return /^https:\/\//i.test(String(this.endpointGetter() || "").trim());
    }

    prune(now = Date.now()) {
      const floor = now - 60000;
      this.calls = this.calls.filter(ts => ts >= floor);
      this.tokenReservations = this.tokenReservations.filter(row => row.ts >= floor);
    }

    reserve(estimatedTokens) {
      this.prune();
      if (this.inFlight >= LIMITS.maxConcurrent) {
        this.stats.budgetRejected++;
        throw new Error(`P6 concurrency budget exceeded (${LIMITS.maxConcurrent})`);
      }
      if (this.calls.length >= LIMITS.maxCallsPerMinute) {
        this.stats.budgetRejected++;
        throw new Error(`P6 calls/min budget exceeded (${LIMITS.maxCallsPerMinute})`);
      }
      if (estimatedTokens > LIMITS.maxInputTokensPerCall) {
        this.stats.budgetRejected++;
        throw new Error(`P6 input token estimate exceeds per-call cap (${estimatedTokens} > ${LIMITS.maxInputTokensPerCall})`);
      }
      const minuteTokens = this.tokenReservations.reduce((sum, row) => sum + row.tokens, 0);
      if (minuteTokens + estimatedTokens > LIMITS.maxEstimatedTokensPerMinute) {
        this.stats.budgetRejected++;
        throw new Error(`P6 token/min budget exceeded (${minuteTokens + estimatedTokens} > ${LIMITS.maxEstimatedTokensPerMinute})`);
      }
      const now = Date.now();
      this.calls.push(now);
      this.tokenReservations.push({ ts: now, tokens: estimatedTokens });
      this.stats.estimatedInputTokens += estimatedTokens;
    }

    identityFor(request) {
      const currentRuntime = this.runtimeGetter();
      const runEpoch = currentRuntime.decisionRouter.epoch;
      return Object.freeze({
        simulationId: request.simulation.id,
        runEpoch,
        agentId: request.agent.id,
        sessionId: request.sessionId,
        requestId: request.requestId,
        observationId: `${request.simulation.id}:${request.simulation.tick}:${request.agent.id}`,
        deadlineTick: request.simulation.tick + CONFIG.maxDecisionAge
      });
    }

    validateEnvelope(envelope, expected, currentEpoch) {
      const errors = [];
      const got = envelope?.identity || {};
      const check = (ok, message) => { if (!ok) errors.push(message); };
      check(envelope?.protocol === "astralife.provider-response.p6", "P6 response protocol mismatch");
      check(same(got.simulationId, expected.simulationId), "P6 simulationId mismatch");
      check(Number(got.runEpoch) === Number(expected.runEpoch), "P6 runEpoch mismatch");
      check(Number(got.agentId) === Number(expected.agentId), "P6 agentId mismatch");
      check(same(got.sessionId, expected.sessionId), "P6 sessionId mismatch");
      check(same(got.requestId, expected.requestId), "P6 requestId mismatch");
      check(same(got.observationId, expected.observationId), "P6 observationId mismatch");
      check(Number(got.deadlineTick) === Number(expected.deadlineTick), "P6 deadlineTick mismatch");
      check(Number(currentEpoch) === Number(expected.runEpoch), "P6 old-epoch response rejected");
      check(!!envelope?.response && typeof envelope.response === "object", "P6 decision response missing");
      if (errors.length) {
        this.stats.rejectedEnvelopes++;
        throw new Error(errors.join(" | "));
      }
      return true;
    }

    retryDelay(requestId, attempt, response) {
      const raw = Number(response?.headers?.get?.("retry-after"));
      if (Number.isFinite(raw) && raw >= 0) return Math.min(LIMITS.retryDelayCapMs, raw * 1000);
      const jitter = Math.abs(hashSeed(`${requestId}|${attempt}|p6`)) % 240;
      return Math.min(LIMITS.retryDelayCapMs, 350 * (attempt + 1) + jitter);
    }

    async fetchOnce(endpoint, payload, requestId) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), CONFIG.providerTimeoutMs);
      try {
        return await fetch(endpoint, {
          method: "POST",
          headers: { "content-type": "application/json", "accept": "application/json" },
          body: JSON.stringify(payload),
          signal: controller.signal,
          credentials: "omit",
          cache: "no-store",
          referrerPolicy: "no-referrer"
        });
      } catch (error) {
        if (error?.name === "AbortError") {
          this.stats.timeouts++;
          throw new Error(`P6 provider timeout for ${requestId}`);
        }
        throw error;
      } finally {
        clearTimeout(timer);
      }
    }

    async decide(request) {
      const endpoint = String(this.endpointGetter() || "").trim();
      if (!endpoint) throw new Error("P6 Typhoon endpoint is empty");
      const estimatedTokens = estimateTokens(request);
      this.reserve(estimatedTokens);
      const identity = this.identityFor(request);
      const payload = { protocol: "astralife.provider-request.p6", identity, request };
      this.inFlight++;
      this.stats.calls++;
      let lastError = null;

      try {
        for (let attempt = 0; attempt <= LIMITS.maxRetries; attempt++) {
          if (this.runtimeGetter().decisionRouter.epoch !== identity.runEpoch) {
            throw new Error("P6 request became stale after runtime epoch changed");
          }
          try {
            const response = await this.fetchOnce(endpoint, payload, request.requestId);
            const text = await response.text();
            if (text.length > CONFIG.maxRemoteResponseBytes * 2) throw new Error("P6 response exceeds bridge size limit");
            if (response.status === 429) {
              this.stats.rateLimited++;
              if (attempt < LIMITS.maxRetries) {
                this.stats.retries++;
                await delay(this.retryDelay(request.requestId, attempt, response));
                continue;
              }
              throw new Error("P6 provider HTTP 429 after bounded retry");
            }
            if (!response.ok) throw new Error(`P6 provider HTTP ${response.status}: ${text.slice(0, 180)}`);
            let envelope;
            try { envelope = JSON.parse(text); }
            catch (error) { throw new Error(`P6 provider returned invalid JSON: ${error.message}`); }
            this.validateEnvelope(envelope, identity, this.runtimeGetter().decisionRouter.epoch);
            if (this.runtimeGetter().state.tick > identity.deadlineTick) throw new Error("P6 response arrived after decision deadline");
            envelope.response.diagnostics = {
              ...(envelope.response.diagnostics || {}),
              p6: {
                version: VERSION,
                model: envelope.providerModel || null,
                runEpoch: identity.runEpoch,
                usage: envelope.usage || null
              }
            };
            this.stats.successes++;
            this.stats.actualTokens += Number(envelope?.usage?.total_tokens || 0);
            this.stats.lastModel = envelope.providerModel || null;
            this.stats.lastError = null;
            return envelope.response;
          } catch (error) {
            lastError = error instanceof Error ? error : new Error(String(error));
            if (attempt < LIMITS.maxRetries && /timeout|network|fetch/i.test(lastError.message)) {
              this.stats.retries++;
              await delay(this.retryDelay(request.requestId, attempt, null));
              continue;
            }
            throw lastError;
          }
        }
        throw lastError || new Error("P6 provider failed without response");
      } catch (error) {
        this.stats.providerErrors++;
        this.stats.lastError = String(error?.message || error);
        throw error;
      } finally {
        this.inFlight = Math.max(0, this.inFlight - 1);
      }
    }

    snapshot() {
      this.prune();
      return {
        version: VERSION,
        configured: this.isConfigured(),
        endpoint: String(this.endpointGetter() || "").trim(),
        limits: { ...LIMITS },
        inFlight: this.inFlight,
        callsLastMinute: this.calls.length,
        estimatedTokensLastMinute: this.tokenReservations.reduce((sum, row) => sum + row.tokens, 0),
        stats: { ...this.stats }
      };
    }
  }

  const provider = new TyphoonP6Provider(() => runtime.providerEndpoint, runtimeRef);
  if (!runtime.providerEndpoint) runtime.setProviderEndpoint(DEFAULT_ENDPOINT);
  window.AstraColony.registerProvider("typhoon", provider, {
    label: "Typhoon 2.5 · P6 isolated bridge",
    async: true,
    description: "Real remote provider via Supabase Edge Function with identity isolation and bounded budgets"
  });

  const oldSnapshot = runtime.snapshot.bind(runtime);
  runtime.snapshot = function() {
    const snap = oldSnapshot();
    snap.provider.p6 = provider.snapshot();
    return snap;
  };

  window.AstraLifeP6 = Object.freeze({
    version: VERSION,
    defaultEndpoint: DEFAULT_ENDPOINT,
    limits: { ...LIMITS },
    providerId: "typhoon",
    mode: "provider:typhoon",
    configure: endpoint => runtime.setProviderEndpoint(String(endpoint || "").trim()),
    enable: () => { runtime.setProviderMode("provider:typhoon"); return runtime.decisionRouter.mode; },
    disable: () => { runtime.setProviderMode(PROVIDER_MODE.LOCAL); return runtime.decisionRouter.mode; },
    status: () => provider.snapshot(),
    identityFor: request => ({ ...provider.identityFor(request) }),
    validateEnvelopeForTest: (envelope, expected, currentEpoch = runtime.decisionRouter.epoch) => {
      try { provider.validateEnvelope(envelope, expected, currentEpoch); return { ok: true, errors: [] }; }
      catch (error) { return { ok: false, errors: String(error.message || error).split(" | ") }; }
    }
  });
})();

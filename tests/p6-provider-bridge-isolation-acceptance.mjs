import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const pageErrors = [];
  const page = await browser.newPage();
  page.on('pageerror', error => pageErrors.push(String(error?.stack || error)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(() => window.AstraLifeP6);

  const result = await page.evaluate(async () => {
    const failures = [];
    const check = (name, condition, detail = {}) => { if (!condition) failures.push({ name, detail }); };
    runtime.state.running = false;
    runtime.reset('P6-provider-isolation-20260909');
    runtime.state.running = false;

    const agent = runtime.state.agents[0];
    const observation = runtime.observer.capture(runtime.state, agent);
    const request = runtime.requestFactory.build(runtime.state, agent, observation, 'typhoon');
    const identity = window.AstraLifeP6.identityFor(request);
    const decisionResponse = {
      protocol: PROTOCOL.decisionResponse,
      requestId: request.requestId,
      agentId: request.agent.id,
      tick: request.simulation.tick,
      provider: 'typhoon',
      decision: {
        action: { protocol: PROTOCOL.action, type: ACTION.WAIT, payload: {} },
        cognition: { goal: 'observe safely', reason: 'bounded P6 test', plan: 'WAIT then re-observe' },
        reason: 'bounded P6 test',
        confidence: 0.75,
        replanAfterTicks: 12
      },
      diagnostics: {}
    };
    const envelope = {
      protocol: 'astralife.provider-response.p6',
      identity: { ...identity },
      providerModel: 'typhoon-v2.5-30b-a3b-instruct',
      usage: { total_tokens: 42 },
      response: JSON.parse(JSON.stringify(decisionResponse))
    };

    // API-01: exact identity passes; wrong agent/session cannot reach the validator.
    const valid = window.AstraLifeP6.validateEnvelopeForTest(envelope, identity);
    const wrongAgent = JSON.parse(JSON.stringify(envelope)); wrongAgent.identity.agentId += 1;
    const wrongSession = JSON.parse(JSON.stringify(envelope)); wrongSession.identity.sessionId += ':wrong';
    const wrongAgentResult = window.AstraLifeP6.validateEnvelopeForTest(wrongAgent, identity);
    const wrongSessionResult = window.AstraLifeP6.validateEnvelopeForTest(wrongSession, identity);
    check('API01_exactIdentityAccepted', valid.ok === true, { valid });
    check('API01_wrongAgentRejected', wrongAgentResult.ok === false && wrongAgentResult.errors.some(x => x.includes('agentId mismatch')), { wrongAgentResult });
    check('API01_wrongSessionRejected', wrongSessionResult.ok === false && wrongSessionResult.errors.some(x => x.includes('sessionId mismatch')), { wrongSessionResult });

    // API-03: first 429 is retried once, then a valid response succeeds.
    const originalFetch = window.fetch;
    let fetchCalls = 0;
    window.fetch = async () => {
      fetchCalls++;
      if (fetchCalls === 1) return new Response(JSON.stringify({ error: 'rate limited' }), { status: 429, headers: { 'retry-after': '0', 'content-type': 'application/json' } });
      return new Response(JSON.stringify(envelope), { status: 200, headers: { 'content-type': 'application/json' } });
    };
    let accepted = null, acceptedError = null;
    try { accepted = await window.AstraLifeP6.decideForTest(request); }
    catch (error) { acceptedError = String(error?.message || error); }
    const checked = accepted ? runtime.validator.validate(accepted, request, runtime.state) : { ok: false, errors: [acceptedError] };
    const afterRetry = window.AstraLifeP6.status();
    check('API03_429BoundedRetry', fetchCalls === 2 && accepted?.provider === 'typhoon' && checked.ok === true && afterRetry.stats.retries >= 1 && afterRetry.stats.rateLimited >= 1, { fetchCalls, acceptedError, checked, afterRetry });

    // API-02: completed request IDs are exactly-once at the bridge boundary.
    let duplicateError = null;
    try { await window.AstraLifeP6.decideForTest(request); }
    catch (error) { duplicateError = String(error?.message || error); }
    const afterDuplicate = window.AstraLifeP6.status();
    check('API02_duplicateRequestRejected', /duplicate request rejected/i.test(duplicateError || '') && afterDuplicate.stats.duplicateRejected >= 1, { duplicateError, afterDuplicate });

    // API-02: reset increments router epoch; the pre-reset response is now stale.
    const previousEpoch = identity.runEpoch;
    runtime.reset('P6-provider-isolation-reset-20260909');
    runtime.state.running = false;
    const newEpoch = runtime.decisionRouter.epoch;
    const oldEpochResult = window.AstraLifeP6.validateEnvelopeForTest(envelope, identity, newEpoch);
    check('API02_oldEpochRejectedAfterReset', newEpoch !== previousEpoch && oldEpochResult.ok === false && oldEpochResult.errors.some(x => x.includes('old-epoch')), { previousEpoch, newEpoch, oldEpochResult });

    // API-03: oversized input is rejected before any network call.
    const agent2 = runtime.state.agents[0];
    const observation2 = runtime.observer.capture(runtime.state, agent2);
    const request2 = runtime.requestFactory.build(runtime.state, agent2, observation2, 'typhoon');
    const oversized = JSON.parse(JSON.stringify(request2));
    oversized.requestId = `${request2.requestId}:oversized`;
    oversized.memory.recentEpisodes = [{ event: 'oversized-test', lesson: 'x'.repeat(60000) }];
    let budgetError = null;
    const beforeBudgetFetchCalls = fetchCalls;
    try { await window.AstraLifeP6.decideForTest(oversized); }
    catch (error) { budgetError = String(error?.message || error); }
    const afterBudget = window.AstraLifeP6.status();
    check('API03_tokenBudgetRejectedBeforeFetch', /token estimate exceeds per-call cap/i.test(budgetError || '') && fetchCalls === beforeBudgetFetchCalls && afterBudget.stats.budgetRejected >= 1, { budgetError, beforeBudgetFetchCalls, fetchCalls, afterBudget });

    window.fetch = originalFetch;
    return {
      ok: failures.length === 0,
      failures,
      version: window.AstraLifeP6.version,
      mode: window.AstraLifeP6.mode,
      status: window.AstraLifeP6.status()
    };
  });

  console.log(JSON.stringify({ pageErrors, ...result }, null, 2));
  if (pageErrors.length || !result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}

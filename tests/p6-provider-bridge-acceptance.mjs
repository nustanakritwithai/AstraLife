import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const pageErrors = [];
  const retryCounts = new Map();
  const page = await browser.newPage();
  page.on('pageerror', error => pageErrors.push(String(error?.stack || error)));

  await page.route('https://bridge.test/decide', async route => {
    const request = JSON.parse(route.request().postData() || '{}');
    const id = String(request.requestId || '');
    if(id.includes('timeout-test')){
      await new Promise(resolve => setTimeout(resolve, 220));
    }
    if(id.includes('retry-test')){
      const count = (retryCounts.get(id) || 0) + 1;
      retryCounts.set(id, count);
      if(count === 1){
        await route.fulfill({status:429, headers:{'content-type':'application/json','retry-after':'0'}, body:JSON.stringify({error:'rate limited'})});
        return;
      }
    }
    const x = Number(request.observation?.self?.x || 100);
    const y = Number(request.observation?.self?.y || 100);
    const response = {
      protocol:'astra-colony.decision-response.v1',
      requestId:request.requestId,
      agentId:request.agent.id,
      tick:request.simulation.tick,
      provider:request.simulation.providerHint,
      identity:{...request.identity},
      decision:{
        action:{protocol:request.actionContract.protocol,type:'MOVE',payload:{x:Math.min(request.actionContract.worldBounds.maxX,x+8),y}},
        cognition:{goal:'test move',reason:'mock bridge',plan:'MOVE'},
        reason:'mock bridge',confidence:.8,replanAfterTicks:12
      },
      diagnostics:{actualProvider:'opentyphoon',model:'typhoon-v2.5-30b-a3b-instruct',usage:{promptTokens:100,completionTokens:20,totalTokens:120},bridgeVersion:'p6.0'}
    };
    await route.fulfill({status:200, headers:{'content-type':'application/json'}, body:JSON.stringify(response)});
  });

  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(() => window.AstraLifeP6?.version === 'p6.0');

  const result = await page.evaluate(async () => {
    const failures = [];
    const check = (name, condition, detail={}) => { if(!condition) failures.push({name, detail}); };
    const clone = value => JSON.parse(JSON.stringify(value));
    const makeResponse = (request, identityPatch={}) => ({
      protocol:PROTOCOL.decisionResponse,
      requestId:request.requestId,
      agentId:request.agent.id,
      tick:request.simulation.tick,
      provider:request.simulation.providerHint,
      identity:{...request.identity,...identityPatch},
      decision:{
        action:{protocol:PROTOCOL.action,type:ACTION.MOVE,payload:{x:Math.min(SPACE.width-4,request.observation.self.x+7),y:request.observation.self.y}},
        cognition:{goal:'move safely',reason:'observable target',plan:'MOVE'},
        reason:'observable target',confidence:.8,replanAfterTicks:12
      },
      diagnostics:{actualProvider:'opentyphoon',model:'typhoon-v2.5-30b-a3b-instruct',usage:{totalTokens:120},bridgeVersion:'p6.0'}
    });

    runtime.state.running = false;
    runtime.reset('P6-acceptance-20260909');
    runtime.state.running = false;
    runtime.setProviderEndpoint('https://bridge.test/decide');
    const agent = runtime.state.agents[0];
    const observation = runtime.observer.capture(runtime.state, agent);
    const request = runtime.requestFactory.build(runtime.state, agent, observation, 'typhoon');

    check('identityEnvelopePresent', !!request.identity && request.identity.agentId === agent.id && request.identity.sessionId === agent.runtime.providerSessionId && request.identity.runEpoch === runtime.decisionRouter.epoch && request.identity.deadlineTick > runtime.state.tick, {identity:request.identity});
    check('credentialAbsentFromRequest', !JSON.stringify(request).includes('OPENTYPHOON_API_KEY') && !Object.keys(request).some(key => /key|secret|authorization/i.test(key)), {keys:Object.keys(request)});

    const badAgent = runtime.validator.validate(makeResponse(request,{agentId:agent.id+1}), request, runtime.state);
    const badSession = runtime.validator.validate(makeResponse(request,{sessionId:`${request.identity.sessionId}:wrong`}), request, runtime.state);
    check('API01_wrongAgentRejected', !badAgent.ok && badAgent.errors.some(error => error.includes('identity mismatch: agentId')), badAgent);
    check('API01_wrongSessionRejected', !badSession.ok && badSession.errors.some(error => error.includes('identity mismatch: sessionId')), badSession);

    const validResponse = makeResponse(request);
    const checked = runtime.validator.validate(validResponse, request, runtime.state);
    check('validP6ResponseAccepted', checked.ok, checked);
    const queue = new ActionQueue();
    const task = {kind:'response',agent,observation,summary:{},context:{planner:runtime.planner},request,providerId:'typhoon',rawResponse:validResponse};
    runtime.decisionRouter.applyAccepted(runtime.state, task, checked.normalized, queue, false);
    runtime.decisionRouter.applyAccepted(runtime.state, task, checked.normalized, queue, false);
    const duplicateActions = queue.drain();
    check('API02_duplicateProducesOnlyOneProviderAction', duplicateActions.filter(action => action.type === ACTION.MOVE).length === 1 && duplicateActions.filter(action => action.type === ACTION.WAIT).length === 1, {duplicateActions});
    check('providerModelRecorded', agent.runtime.providerActual === 'opentyphoon' && agent.runtime.providerModel === 'typhoon-v2.5-30b-a3b-instruct', {actual:agent.runtime.providerActual,model:agent.runtime.providerModel});

    const oldRequest = request;
    const oldResponse = validResponse;
    const oldEpoch = oldRequest.identity.runEpoch;
    runtime.reset('P6-acceptance-20260909');
    runtime.state.running = false;
    const newAgent = runtime.state.agents[0];
    const newObservation = runtime.observer.capture(runtime.state, newAgent);
    const newRequest = runtime.requestFactory.build(runtime.state, newAgent, newObservation, 'typhoon');
    const stale = runtime.validator.validate(oldResponse, newRequest, runtime.state);
    check('API02_oldEpochRejectedAfterReset', newRequest.identity.runEpoch > oldEpoch && !stale.ok && stale.errors.some(error => error.includes('requestId mismatch') || error.includes('identity mismatch: runEpoch')), {oldEpoch,newEpoch:newRequest.identity.runEpoch,errors:stale.errors});

    const adapter = window.AstraLifeP6.createTestAdapter(() => 'https://bridge.test/decide', {maxConcurrent:1,maxQueue:4,maxCallsPerMinute:10,retryLimit:1,retryBaseMs:1,requestTimeoutMs:200});
    const retryRequest = clone(newRequest);
    retryRequest.requestId = `${newRequest.requestId}:retry-test`;
    retryRequest.identity.requestId = retryRequest.requestId;
    retryRequest.providerBudget.retryLimit = 1;
    retryRequest.providerBudget.timeoutMs = 200;
    const retried = await adapter.decide(retryRequest);
    const retryStats = adapter.snapshot();
    check('API03_429RetriesBoundedAndSucceeds', retried.requestId === retryRequest.requestId && retryStats.retries === 1 && retryStats.rateLimited === 1, {retryStats,retried});

    const timeoutAdapter = window.AstraLifeP6.createTestAdapter(() => 'https://bridge.test/decide', {maxConcurrent:1,maxQueue:2,maxCallsPerMinute:10,retryLimit:0,retryBaseMs:1,requestTimeoutMs:100});
    const timeoutRequest = clone(newRequest);
    timeoutRequest.requestId = `${newRequest.requestId}:timeout-test`;
    timeoutRequest.identity.requestId = timeoutRequest.requestId;
    timeoutRequest.providerBudget.retryLimit = 0;
    timeoutRequest.providerBudget.timeoutMs = 100;
    let timeoutError = null;
    try{ await timeoutAdapter.decide(timeoutRequest); }catch(error){ timeoutError = String(error?.message || error); }
    const timeoutStats = timeoutAdapter.snapshot();
    check('API03_timeoutIsBounded', !!timeoutError && timeoutStats.timedOut === 1 && timeoutStats.retries === 0, {timeoutError,timeoutStats});

    const budgetAdapter = window.AstraLifeP6.createTestAdapter(() => 'https://bridge.test/decide', {maxConcurrent:0,maxQueue:1,maxCallsPerMinute:1});
    budgetAdapter.decide(newRequest).catch(() => {});
    let budgetError = null;
    try{ await budgetAdapter.decide(newRequest); }catch(error){ budgetError = String(error?.message || error); }
    check('API03_queueBudgetExhaustionIsImmediate', /queue budget exhausted/i.test(budgetError || ''), {budgetError,stats:budgetAdapter.snapshot()});

    const fallbackQueue = new ActionQueue();
    const fallbackTask = {kind:'error',agent:newAgent,observation:newObservation,summary:{alive:runtime.state.agents.length},context:{planner:runtime.planner},request:newRequest,providerId:'typhoon',error:new Error('P6 synthetic timeout')};
    runtime.decisionRouter.fallbackLocal(runtime.state, fallbackTask, fallbackQueue, 'P6 synthetic timeout');
    const fallbackActions = fallbackQueue.drain();
    check('API03_failureFallsBackLocally', fallbackActions.length === 1 && fallbackActions[0].meta?.fallback === true && fallbackActions[0].meta?.provider === 'local', {fallbackActions});

    return {failures, identity:request.identity, retryStats, timeoutStats, fallbackActions:fallbackActions.map(action=>({type:action.type,provider:action.meta?.provider,fallback:action.meta?.fallback}))};
  });

  if(pageErrors.length) throw new Error(`page errors: ${pageErrors.join('\n')}`);
  if(result.failures.length) throw new Error(`P6 acceptance failed:\n${JSON.stringify(result.failures,null,2)}`);
  console.log('P6 provider bridge acceptance PASS');
  console.log(JSON.stringify(result,null,2));
} finally {
  await browser.close();
}

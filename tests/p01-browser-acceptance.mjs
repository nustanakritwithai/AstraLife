import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  page.on('pageerror', err => console.error('[browser:error]', err));
  await page.goto(pathToFileURL(path.resolve('index.html')).href, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.AstraLifeKnowledgeBoundary && !!window.AstraLifeV051Acceptance, null, { timeout: 15000 });

  const result = await page.evaluate(() => {
    runtime.state.running = false;

    const seed = 'P01-KNOWLEDGE-CI';
    const left = new WorldRuntime(seed);
    const right = new WorldRuntime(seed);
    left.setProviderMode(PROVIDER_MODE.LOCAL);
    right.setProviderMode(PROVIDER_MODE.LOCAL);

    const aL = left.state.agents[0], aR = right.state.agents[0];
    aL.body.x = aR.body.x = 40;
    aL.body.y = aR.body.y = 40;

    const victimL = left.state.agents[1], victimR = right.state.agents[1];
    victimL.body.x = victimR.body.x = left.state.camp.x;
    victimL.body.y = victimR.body.y = left.state.camp.y;
    victimR.alive = false;

    right.state.stock.food += 999;
    right.state.stock.water += 999;

    const farResourceL = left.state.resources.find(r => Math.hypot(r.x-aL.body.x, r.y-aL.body.y) > CONFIG.observationRange + 50);
    const farResourceR = farResourceL ? right.state.resourceById.get(farResourceL.id) : null;
    if (farResourceR) farResourceR.amount = Math.max(.1, farResourceR.amount * .1);

    left.state.stormTicks = 120;
    right.state.stormTicks = 45;

    const obsL = left.observer.capture(left.state, aL);
    const obsR = right.observer.capture(right.state, aR);
    const obsEqual = JSON.stringify(obsL) === JSON.stringify(obsR);
    const reqL = left.requestFactory.build(left.state, aL, obsL, 'local');
    const reqR = right.requestFactory.build(right.state, aR, obsR, 'local');
    const reqEqual = JSON.stringify(reqL) === JSON.stringify(reqR);

    const sourceL = left.state.agents[2], sourceR = right.state.agents[2];
    sourceL.social.reputation.credibility = .08;
    sourceR.social.reputation.credibility = .98;
    const packet = Object.freeze({
      protocol: PROTOCOL.communication,
      id: 99001,
      from: sourceL.id,
      to: aL.id,
      intent: 'REPORT',
      tick: 0,
      urgency: .5,
      text: 'water report',
      replyTo: null,
      facts: Object.freeze([Object.freeze({key:'resource:99901',value:Object.freeze({id:99901,type:'water',x:600,y:200,amountBand:'high'}),confidence:.8})])
    });
    aL.social.inbox.push(packet);
    aR.social.inbox.push(Object.freeze({...packet, from: sourceR.id, to: aR.id}));
    const msgObsL = left.observer.capture(left.state, aL);
    const msgObsR = right.observer.capture(right.state, aR);
    left.memory.ingest(aL, msgObsL, left.state);
    right.memory.ingest(aR, msgObsR, right.state);
    const cL = aL.mind.facts.get('resource:99901')?.confidence;
    const cR = aR.mind.facts.get('resource:99901')?.confidence;
    const hiddenReputationIgnored = cL === cR;

    const preparedL = left.decisionRouter.prepare(left.state,{agent:aL,observation:obsL,planner:left.planner},{alive:9999});
    const preparedR = right.decisionRouter.prepare(right.state,{agent:aR,observation:obsR,planner:right.planner},{alive:1});
    const localSummaryOnly = preparedL.context.summary.alive === preparedR.context.summary.alive && preparedL.context.summary.scope === 'LOCAL_VISIBLE_ESTIMATE';

    const tests = {
      OBS01_observationUnchangedByHiddenWorldTruth: obsEqual,
      OBS01_requestUnchangedByHiddenWorldTruth: reqEqual,
      hiddenGlobalReputationIgnored: hiddenReputationIgnored,
      plannerSummaryUsesLocalVisibleEstimate: localSummaryOnly,
      exactStormCountdownHidden: obsL.environment.stormTicks === null && obsR.environment.stormTicks === null,
      remoteCampStockHidden: obsL.camp.stock === null && obsR.camp.stock === null,
      globalAliveNotExposed: reqL.simulation.alive === 1 + obsL.nearbyAgents.length && reqR.simulation.alive === 1 + obsR.nearbyAgents.length
    };
    return {ok:Object.values(tests).every(Boolean),tests,observationsEqual:obsEqual,requestsEqual:reqEqual,messageConfidence:{left:cL,right:cR},publicKnowledge:window.AstraLifeKnowledgeBoundary.publicKnowledge};
  });

  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}

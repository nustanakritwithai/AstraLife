import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',error=>pageErrors.push(String(error?.stack||error)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraColony&&window.AstraLifeTurnAhead&&window.AstraLifeFramePacing);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    window.AstraColony.reset('P61-TURN-AHEAD-20260909');
    runtime.state.running=false;

    const providerId='turn-test';
    window.AstraColony.registerProvider(providerId,{
      async decide(request){
        return makeDecisionResponse(
          request,
          providerId,
          {type:ACTION.WAIT,payload:{},reason:'staged one turn ahead'},
          {goal:'think_ahead',reason:'prepare next turn',plan:'WAIT next turn'},
          .8,
          1,
          {engine:'turn-ahead-test'}
        );
      }
    },{label:'Turn Ahead Test',async:true});
    runtime.setProviderMode(`provider:${providerId}`);

    const startActions=runtime.state.metrics.totalActions;
    const firstOutcomes=runtime.tickOnce();
    const afterFirst=window.AstraLifeTurnAhead.status();
    const firstActions=runtime.state.metrics.totalActions;
    await new Promise(resolve=>setTimeout(resolve,0));
    const afterFirstThink=window.AstraLifeTurnAhead.status();

    const secondOutcomes=runtime.tickOnce();
    const afterSecond=window.AstraLifeTurnAhead.status();
    const secondActions=runtime.state.metrics.totalActions;
    await new Promise(resolve=>setTimeout(resolve,0));
    const afterSecondThink=window.AstraLifeTurnAhead.status();

    const thirdOutcomes=runtime.tickOnce();
    const afterThird=window.AstraLifeTurnAhead.status();
    const thirdActions=runtime.state.metrics.totalActions;

    check('turn1ThinksButDoesNotAct',firstOutcomes.length===0&&firstActions===startActions,{firstOutcomes,firstActions,startActions,afterFirst});
    check('turn1ProducesStagedPlans',afterFirstThink.ready>0&&afterFirstThink.pending===0,{afterFirstThink});
    check('turn2ExecutesTurn1Plan',secondOutcomes.length>0&&secondActions>firstActions&&afterSecond.lastExecutedCount>0,{secondOutcomes:secondOutcomes.length,firstActions,secondActions,afterSecond});
    check('turn2AlsoThinksForTurn3',afterSecondThink.ready>0&&afterSecondThink.lastThinkTick===runtime.state.tick,{afterSecondThink});
    check('turn3ExecutesTurn2Plan',thirdOutcomes.length>0&&thirdActions>secondActions&&afterThird.lastExecutedCount>0,{thirdOutcomes:thirdOutcomes.length,secondActions,thirdActions,afterThird});
    check('eightSecondCadence',window.AstraLifeFramePacing.config.intervalMs===8000&&window.AstraLifeFramePacing.config.simulationTicksPerSecond===.125,{config:window.AstraLifeFramePacing.config});
    check('policyIsOneTurnAhead',/N\+1/.test(window.AstraLifeTurnAhead.policy),{policy:window.AstraLifeTurnAhead.policy});

    return {ok:failures.length===0,failures,firstActions,secondActions,thirdActions,afterFirst,afterFirstThink,afterSecond,afterSecondThink,afterThird};
  });

  console.log(JSON.stringify({pageErrors,...result},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

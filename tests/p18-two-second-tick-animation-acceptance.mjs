import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraColony&&window.AstraLifeFramePacing);
  const result=await page.evaluate(()=>{
    const scheduler=window.AstraLifeFramePacing;
    const colony=window.AstraColony;
    runtime.state.running=false;
    colony.reset('P18-TWO-SECOND-TICK-20260907');
    runtime.state.running=false;
    scheduler.reset();
    const config=scheduler.config;
    const startTick=runtime.state.tick;
    const agentId=runtime.state.agents[0].id;
    const firstBody={...runtime.state.agents[0].body};
    for(let i=0;i<20;i++)scheduler.advanceForTest(100);
    const afterTick=runtime.state.tick;
    const atTickVisual=scheduler.getVisualState();
    const bodyAtTick={...runtime.state.agents[0].body};
    const renderFirst=render();
    let halfway;for(let i=0;i<10;i++)halfway=scheduler.advanceForTest(100);
    const afterHalfTick=runtime.state.tick;
    const visualHalf=scheduler.getVisualState();
    const positionHalf=scheduler.getInterpolatedAgentPosition(agentId);
    const bodyAfterHalf={...runtime.state.agents[0].body};
    const tickStableDuringHalf=runtime.state.tick===afterHalfTick;
    const renderSecond=render();
    const tickBeforeApi=runtime.state.tick;
    runtime.tickOnce();
    const afterStep=runtime.state.tick;
    runtime.runTicks(3);
    const afterRunTicks=runtime.state.tick;
    const bodyStable=JSON.stringify(bodyAtTick)===JSON.stringify(bodyAfterHalf);
    const positionFinite=positionHalf&&Number.isFinite(positionHalf.x)&&Number.isFinite(positionHalf.y);
    const tests={
      cadenceIsHalfTickPerSecond:config.intervalMs===2000&&Math.abs(config.simulationTicksPerSecond-.5)<1e-9,
      authoritativeTickArrivedAfterTwoSeconds:afterTick===startTick+1,
      noTickDuringInterpolationWindow:afterHalfTick===afterTick,
      alphaInRange:.45<=visualHalf.alpha&&visualHalf.alpha<=.55,
      snapshotTicksAdvanceTogether:atTickVisual.previousTick===startTick&&atTickVisual.nextTick===afterTick,
      interpolationDoesNotMutateWorldState:bodyStable&&tickStableDuringHalf,
      interpolatedPositionIsFinite:positionFinite,
      renderContinuesWithoutTick:renderFirst===true&&renderSecond===true,
      tickStepApiPreserved:afterStep===tickBeforeApi+1&&afterRunTicks===tickBeforeApi+4,
      initialBodySnapshotFinite:Number.isFinite(firstBody.x)&&Number.isFinite(firstBody.y),
      schedulerGuardrailsPreserved:config.maxTicksPerFrame===2&&config.maxBacklogTicks===6
    };
    return {ok:Object.values(tests).every(Boolean),tests,config,halfway,visualHalf,startTick,afterTick,afterHalfTick,afterStep,afterRunTicks};
  });
  console.log(JSON.stringify(result,null,2));
  if(!result.ok)process.exitCode=1;
}finally{await browser.close()}

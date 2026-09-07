import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraColony&&window.AstraLifeFramePacing);
  const result=await page.evaluate(()=>{
    runtime.state.running=false;
    runtime.reset('P14-FRAME-PACING-20260907');
    runtime.state.running=false;
    const scheduler=window.AstraLifeFramePacing;
    const config=scheduler.config;
    scheduler.reset();
    runtime.state.speed=8;
    const startTick=runtime.state.tick;
    for(let i=0;i<24;i++)scheduler.advanceForTest(100);
    const stats=scheduler.getStats();
    const tickAfterBurstTest=runtime.state.tick;
    runtime.state.running=false;
    runtime.reset('P14-TICK-API-20260907');
    runtime.state.running=false;
    const tickStart=runtime.state.tick;
    runtime.tickOnce();
    const afterStep=runtime.state.tick;
    runtime.runTicks(3);
    const afterRunTicks=runtime.state.tick;
    const tests={
      maxTicksPerFrameAtMostTwo:stats.maxTicksPerFrame<=2&&stats.maxTicksPerFrame<=config.maxTicksPerFrame,
      boundedBacklog:stats.maxBacklogTicks<=config.maxBacklogTicks+1e-9&&stats.backlogTicks<=config.maxBacklogTicks+1e-9,
      noUnboundedCatchUp:stats.droppedTicks>0&&stats.frames===24&&stats.maxBacklogTicks<=config.maxBacklogTicks+1e-9,
      speedStillAdvances:tickAfterBurstTest>startTick,
      tickStepApiPreserved:afterStep===tickStart+1&&afterRunTicks===tickStart+4,
      measurableSchedulerStats:stats.totalTicks===tickAfterBurstTest-startTick
    };
    return {ok:Object.values(tests).every(Boolean),tests,config,stats,tickStart,afterStep,afterRunTicks};
  });
  console.log(JSON.stringify(result,null,2));
  if(!result.ok)process.exitCode=1;
}finally{await browser.close()}

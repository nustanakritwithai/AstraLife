import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeTyphoonQueue&&window.AstraLifeTyphoonBYOK&&window.AstraColony);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.5-BYOK-QUEUE-20260909');
    runtime.state.running=false;

    let activeFetch=0,maxFetch=0,totalFetch=0;
    globalThis.fetch=async()=>{
      activeFetch++;totalFetch++;maxFetch=Math.max(maxFetch,activeFetch);
      await new Promise(r=>setTimeout(r,35));
      activeFetch--;
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          choices:[{message:{content:JSON.stringify({
            action:{type:'WAIT',payload:{}},thought:'I will watch what happens next.',goal:'observe',reason:'I need more evidence',plan:'wait and observe',confidence:.8,replanAfterTicks:12
          })}}]
        })
      };
    };

    window.AstraLifeTyphoonBYOK.setKey('test-key-not-secret-123456789');
    window.AstraLifeTyphoonBYOK.enable();
    const provider=runtime.registry.get('typhoon-byok').adapter;
    const agents=runtime.state.agents.slice(0,12);
    const requests=agents.map(agent=>{
      const obs=runtime.observer.capture(runtime.state,agent);
      return runtime.requestFactory.build(runtime.state,agent,obs,'typhoon-byok');
    });
    const promises=requests.map(req=>provider.decide(req,{}));

    await new Promise(r=>setTimeout(r,8));
    const queuedEarly=window.AstraLifeTyphoonQueue.status();
    const responses=await Promise.all(promises);
    const final=window.AstraLifeTyphoonQueue.status();

    check('allRequestsReachRealProvider',responses.length===12&&responses.every(r=>r.provider==='typhoon-byok'),{responses:responses.length});
    check('browserConcurrencyIsBounded',maxFetch<=3,{maxFetch});
    check('excessRequestsQueueInsteadOfRejecting',queuedEarly.queueDepth>0&&queuedEarly.active<=3,{queuedEarly});
    check('queueFullyDrains',final.queueDepth===0&&final.active===0,{final});
    check('noQueueFailures',final.stats.failed===0,{final});
    check('upstreamShowsSuccesses',Number(final.upstream?.stats?.successes||0)>=12,{upstream:final.upstream});
    check('apiWasActuallyCalled',totalFetch===12,{totalFetch});

    return {ok:failures.length===0,failures,maxFetch,totalFetch,queuedEarly,final,pageErrors:[]};
  });
  console.log(JSON.stringify({...result,pageErrors},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

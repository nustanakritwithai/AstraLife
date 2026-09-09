import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeTyphoonQueue&&window.AstraLifeLLMGate&&window.AstraLifeTyphoonBYOK&&window.AstraColony);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.8-FULL-THROUGHPUT-20260909');
    runtime.state.running=false;

    let activeFetch=0,maxFetch=0,totalFetch=0;
    globalThis.fetch=async(_url,options={})=>{
      activeFetch++;totalFetch++;maxFetch=Math.max(maxFetch,activeFetch);
      const body=JSON.parse(String(options.body||'{}'));
      const latest=[...(body.messages||[])].reverse().find(m=>m.role==='user')?.content||'';
      const id=Number(latest.match(/\"agent\":\{\"id\":(\d+)/)?.[1]||0);
      await new Promise(r=>setTimeout(r,80));
      activeFetch--;
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          choices:[{message:{content:JSON.stringify({
            action:{type:'WAIT',payload:{}},thought:`Agent ${id} processed at full throughput.`,goal:'observe',reason:'test',plan:'wait',confidence:.8,replanAfterTicks:12
          })}}]
        })
      };
    };

    window.AstraLifeTyphoonBYOK.setKey('test-key-not-secret-123456789');
    window.AstraLifeTyphoonBYOK.enable();
    const provider=runtime.registry.get('typhoon-byok').adapter;
    const agents=runtime.state.agents.slice(0,60);
    for(const a of agents)a.mind.replanAtTick=999;
    const makeRequest=agent=>runtime.requestFactory.build(runtime.state,agent,runtime.observer.capture(runtime.state,agent),'typhoon-byok');

    const promises=agents.map(a=>provider.decide(makeRequest(a),{agent:a}));
    await new Promise(r=>setTimeout(r,12));
    const early=window.AstraLifeTyphoonQueue.status();
    const earlyActiveFetch=activeFetch;
    const responses=await Promise.all(promises);
    const afterBootstrap=window.AstraLifeTyphoonQueue.status();
    const fetchAfterBootstrap=totalFetch;

    check('fullPoolActuallyUsed',early.active>3&&earlyActiveFetch>3,{active:early.active,activeFetch:earlyActiveFetch});
    check('fullPoolBounded',early.active<=48&&maxFetch<=48,{active:early.active,maxFetch});
    check('bootstrapDoesNotBatchByTen',early.active>=24,{active:early.active,lanes:early.lanes});
    check('initialQueueIsOnlyTailOfPool',early.queueDepth<=12,{queueDepth:early.queueDepth,active:early.active});
    check('lanesRunInParallel',early.lanes?.length===3&&early.lanes.every(l=>l.active>=8),{lanes:early.lanes});
    check('all60ReachRealTyphoon',responses.length===60&&responses.every(r=>r.provider==='typhoon-byok')&&totalFetch===60,{responses:responses.length,totalFetch});
    check('queueDrains',afterBootstrap.active===0&&afterBootstrap.queueDepth===0,{afterBootstrap});
    check('dispatcherReports48Max',afterBootstrap.limits?.maxActiveTotal===48,{limits:afterBootstrap.limits});
    check('upstreamRaisedTo48',afterBootstrap.upstream?.limits?.maxConcurrent===48,{upstreamLimits:afterBootstrap.upstream?.limits});
    check('rpmHeadroomIs195',afterBootstrap.limits?.maxCallsPerMinute===195&&afterBootstrap.upstream?.limits?.maxCallsPerMinute===195,{dispatcher:afterBootstrap.limits,upstream:afterBootstrap.upstream?.limits});

    runtime.state.tick++;
    const stable=agents[0];
    const reused=await provider.decide(makeRequest(stable),{agent:stable});
    check('stablePlanReusesWithoutNetwork',totalFetch===fetchAfterBootstrap&&reused.diagnostics?.decisionSource==='cached-llm-reuse',{totalFetch,fetchAfterBootstrap,diagnostics:reused.diagnostics});

    stable.runtime.lastOutcome={actionId:'p68-fail-1',agentId:stable.id,actionType:'WAIT',ok:false,message:'forced failure',significant:true};
    runtime.state.tick++;
    await provider.decide(makeRequest(stable),{agent:stable});
    check('realTriggerStillCallsModelImmediately',totalFetch===fetchAfterBootstrap+1,{totalFetch,fetchAfterBootstrap});

    const gate=window.AstraLifeLLMGate.status();
    const byok=window.AstraLifeTyphoonBYOK.status();
    check('noBatchAdmissionPolicy',String(window.AstraLifeLLMGate.policy?.admission||'').includes('no batch/defer'),{policy:window.AstraLifeLLMGate.policy});
    check('noDeferredCounterInGate',gate.stats.deferred===undefined,{gateStats:gate.stats});
    check('independentSessionsPreserved',Number(byok.upstream?.sessions?.count||byok.sessions?.count||0)>=60,{byok});

    return {ok:failures.length===0,failures,totalFetch,maxFetch,early,afterBootstrap,gate:gate.stats,byok,pageErrors:[]};
  });

  console.log(JSON.stringify({...result,pageErrors},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

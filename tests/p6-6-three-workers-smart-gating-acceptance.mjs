import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeTyphoonQueue&&window.AstraLifeLLMGate&&window.AstraLifeTyphoonBYOK);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.6-THREE-WORKERS-SMART-GATE-20260909');
    runtime.state.running=false;

    let activeFetch=0,maxFetch=0,totalFetch=0;
    globalThis.fetch=async(_url,options={})=>{
      activeFetch++;totalFetch++;maxFetch=Math.max(maxFetch,activeFetch);
      const body=JSON.parse(String(options.body||'{}'));
      const latest=[...(body.messages||[])].reverse().find(m=>m.role==='user')?.content||'';
      const id=Number(latest.match(/\"agent\":\{\"id\":(\d+)/)?.[1]||0);
      await new Promise(r=>setTimeout(r,30));
      activeFetch--;
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          choices:[{message:{content:JSON.stringify({
            action:{type:'WAIT',payload:{}},thought:`Agent ${id} is watching carefully.`,goal:'observe',reason:'No urgent change yet',plan:'wait and observe',confidence:.8,replanAfterTicks:12
          })}}]
        })
      };
    };

    window.AstraLifeTyphoonBYOK.setKey('test-key-not-secret-123456789');
    window.AstraLifeTyphoonBYOK.enable();
    const provider=runtime.registry.get('typhoon-byok').adapter;
    const agents=runtime.state.agents.slice(0,9);
    for(const a of agents)a.mind.replanAtTick=999;
    const makeRequest=agent=>runtime.requestFactory.build(runtime.state,agent,runtime.observer.capture(runtime.state,agent),'typhoon-byok');

    const first=agents.map(a=>provider.decide(makeRequest(a),{agent:a}));
    await new Promise(r=>setTimeout(r,6));
    const early=window.AstraLifeTyphoonQueue.status();
    const firstResponses=await Promise.all(first);
    const afterFirstFetch=totalFetch;

    check('threeWorkersExist',early.workers?.length===3,{workers:early.workers});
    check('oneActivePerWorker',early.workers?.every(w=>w.active<=1)&&early.active<=3,{workers:early.workers,active:early.active});
    check('allWorkersReceiveJobs',early.workers?.every(w=>w.active===1&&w.queued>=1),{workers:early.workers});
    check('stableRoundRobinAssignment',
      window.AstraLifeTyphoonQueue.workerForAgent(agents[0].id)==='A'&&
      window.AstraLifeTyphoonQueue.workerForAgent(agents[1].id)==='B'&&
      window.AstraLifeTyphoonQueue.workerForAgent(agents[2].id)==='C'&&
      window.AstraLifeTyphoonQueue.workerForAgent(agents[3].id)==='A',
      {ids:agents.slice(0,4).map(a=>a.id)});
    check('bootstrapCallsAreReal',afterFirstFetch===9&&firstResponses.every(r=>r.provider==='typhoon-byok'),{afterFirstFetch});
    check('globalNetworkConcurrencyBounded',maxFetch<=3,{maxFetch});

    runtime.state.tick++;
    const secondResponses=await Promise.all(agents.map(a=>provider.decide(makeRequest(a),{agent:a})));
    check('stableTurnsReuseWithoutNetwork',totalFetch===afterFirstFetch,{totalFetch,afterFirstFetch});
    check('reusedResponsesReboundToCurrentRequest',secondResponses.every(r=>r.tick===runtime.state.tick&&r.diagnostics?.decisionSource==='cached-llm-reuse'),{tick:runtime.state.tick});

    const failed=agents[0];
    failed.runtime.lastOutcome={actionId:'p66-fail-1',agentId:failed.id,actionType:'WAIT',ok:false,message:'forced test failure',significant:true};
    runtime.state.tick++;
    await provider.decide(makeRequest(failed),{agent:failed});
    check('actionFailureForcesRealReasoning',totalFetch===afterFirstFetch+1,{totalFetch});

    const stale=agents[2];
    stale.runtime.lastOutcome=null;
    stale.mind.replanAtTick=999;
    runtime.state.tick=6;
    await provider.decide(makeRequest(stale),{agent:stale});
    check('maxStaleWindowForcesRefresh',totalFetch===afterFirstFetch+2,{totalFetch});

    const gate=window.AstraLifeLLMGate.status();
    const finalQueue=window.AstraLifeTyphoonQueue.status();
    check('gateCountsRealAndReuse',gate.stats.realCalls>=11&&gate.stats.reuses>=9,{gate:gate.stats});
    check('failureTriggerRecorded',Number(gate.stats.byReason?.['action-failed']||0)>=1,{reasons:gate.stats.byReason});
    check('staleTriggerRecorded',Number(gate.stats.byReason?.['max-stale-refresh']||0)>=1,{reasons:gate.stats.byReason});
    check('queueDrains',finalQueue.active===0&&finalQueue.queueDepth===0,{finalQueue});

    return {ok:failures.length===0,failures,totalFetch,maxFetch,early,gate:gate.stats,finalQueue,pageErrors:[]};
  });

  console.log(JSON.stringify({...result,pageErrors},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

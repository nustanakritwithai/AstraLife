import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeTyphoonQueue&&window.AstraLifeLLMGate&&window.AstraLifeTyphoonBYOK&&window.AstraLifeLLMThoughtBubbles);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.7-STAGGERED-ADMISSION-20260909');
    runtime.state.running=false;
    runtime.selectedAgentId=null;

    let activeFetch=0,maxFetch=0,totalFetch=0;
    const realByAgent=new Map();
    globalThis.fetch=async(_url,options={})=>{
      activeFetch++;totalFetch++;maxFetch=Math.max(maxFetch,activeFetch);
      const body=JSON.parse(String(options.body||'{}'));
      const latest=[...(body.messages||[])].reverse().find(m=>m.role==='user')?.content||'';
      const id=Number(latest.match(/\"agent\":\{\"id\":(\d+)/)?.[1]||0);
      realByAgent.set(id,(realByAgent.get(id)||0)+1);
      await new Promise(r=>setTimeout(r,45));
      activeFetch--;
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          choices:[{message:{content:JSON.stringify({
            action:{type:'WAIT',payload:{}},thought:`A${id} real thought`,goal:'observe',reason:'stable observation',plan:'wait and observe',confidence:.8,replanAfterTicks:20
          })}}]
        })
      };
    };

    window.AstraLifeTyphoonBYOK.setKey('test-key-not-secret-123456789');
    window.AstraLifeTyphoonBYOK.enable();
    const provider=runtime.registry.get('typhoon-byok').adapter;
    const agents=runtime.state.agents.slice(0,18);
    for(const a of agents){a.mind.replanAtTick=999;a.runtime.lastOutcome=null;}
    const requestFor=a=>runtime.requestFactory.build(runtime.state,a,runtime.observer.capture(runtime.state,a),'typhoon-byok');

    let firstTurnResponses=[];
    let maxObservedQueue=0;
    let maxWorkerQueue=0;

    // Six stagger slots: every Agent gets one bootstrap real call, but only one
    // A/B/C triple is admitted per slot for this 18-Agent fixture.
    for(let tick=0;tick<6;tick++){
      runtime.state.tick=tick;
      const responses=await Promise.all(agents.map(a=>provider.decide(requestFor(a),{agent:a})));
      if(tick===0)firstTurnResponses=responses;
      const q=window.AstraLifeTyphoonQueue.status();
      maxObservedQueue=Math.max(maxObservedQueue,q.stats?.maxObservedQueue||0,q.queueDepth||0);
      maxWorkerQueue=Math.max(maxWorkerQueue,...(q.workers||[]).map(w=>w.maxQueue||0));
    }

    const gateAfterBootstrap=window.AstraLifeLLMGate.status();
    const realAgents=[...realByAgent.keys()].sort((a,b)=>a-b);
    const deferredFirst=firstTurnResponses.filter(r=>r.diagnostics?.decisionSource==='deferred-admission');
    const hiddenDeferred=deferredFirst.every(r=>window.AstraLifeLLMThoughtBubbles.extractForTest(r)===null);

    check('bootstrapSpreadUsesSixSlots',gateAfterBootstrap.limits.bootstrapSpreadTicks===6,{limits:gateAfterBootstrap.limits});
    check('balancedSlotsAcrossWorkers',
      window.AstraLifeLLMGate.bootstrapSlotForAgent(1)===0&&
      window.AstraLifeLLMGate.bootstrapSlotForAgent(2)===0&&
      window.AstraLifeLLMGate.bootstrapSlotForAgent(3)===0&&
      window.AstraLifeTyphoonQueue.workerForAgent(1)==='A'&&
      window.AstraLifeTyphoonQueue.workerForAgent(2)==='B'&&
      window.AstraLifeTyphoonQueue.workerForAgent(3)==='C');
    check('everyAgentGetsRealBootstrapAcrossSlots',realAgents.length===18&&agents.every(a=>(realByAgent.get(a.id)||0)>=1),{realAgents});
    check('realFetchesAreSpreadNotBurst',totalFetch===18,{totalFetch});
    check('networkConcurrencyBounded',maxFetch<=3,{maxFetch});
    check('firstTurnDefersNonSlotAgents',deferredFirst.length===15,{deferred:firstTurnResponses.map(r=>r.diagnostics?.decisionSource||'real')});
    check('deferredWaitsDoNotPretendToBeLlmThoughts',hiddenDeferred,{deferredFirst:deferredFirst.length});
    check('bootstrapQueueStaysSmall',maxObservedQueue<=9&&maxWorkerQueue<=3,{maxObservedQueue,maxWorkerQueue});

    // Force a herd-like scheduled replan after every Agent has cache. Admission
    // should back off ordinary replans instead of allowing a long queue.
    runtime.state.tick=30;
    for(const a of agents)a.mind.replanAtTick=30;
    const beforePressureFetch=totalFetch;
    const pressurePromises=agents.map(a=>provider.decide(requestFor(a),{agent:a}));
    await new Promise(r=>setTimeout(r,5));
    const pressureEarly=window.AstraLifeTyphoonQueue.status();
    const pressureResponses=await Promise.all(pressurePromises);
    const afterPressureGate=window.AstraLifeLLMGate.status();
    const pressureReuse=pressureResponses.filter(r=>r.diagnostics?.decisionSource==='cached-llm-admission-reuse').length;

    check('pressureAdmissionCapsQueuedWork',pressureEarly.queueDepth<=9&&(pressureEarly.workers||[]).every(w=>w.queued<=3),{pressureEarly});
    check('pressureUsesCachedPlansInsteadOfLongQueue',pressureReuse>0&&afterPressureGate.stats.pressureReuses>0,{pressureReuse,stats:afterPressureGate.stats});
    check('pressureDoesNotSendAll18AtOnce',totalFetch-beforePressureFetch<18,{newFetches:totalFetch-beforePressureFetch});

    const finalQueue=window.AstraLifeTyphoonQueue.status();
    check('queueDrains',finalQueue.queueDepth===0&&finalQueue.active===0,{finalQueue});

    return {
      ok:failures.length===0,failures,totalFetch,maxFetch,maxObservedQueue,maxWorkerQueue,
      deferredFirst:deferredFirst.length,pressureReuse,pressureEarly,
      gate:afterPressureGate.stats,finalQueue,pageErrors:[]
    };
  });

  console.log(JSON.stringify({...result,pageErrors},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

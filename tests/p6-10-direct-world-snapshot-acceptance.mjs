import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeWorldSnapshot&&window.AstraColony);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.11-SNAPSHOT-GOVERNOR-20260909');
    runtime.state.running=false;

    let fakeNow=1_000_000;
    Date.now=()=>fakeNow;
    let fetchCount=0;
    let lastAuth='';
    let lastBatchSize=0;
    let lastUrl='';

    globalThis.fetch=async(url,options={})=>{
      fetchCount++;
      lastUrl=String(url);
      lastAuth=String(options.headers?.authorization||options.headers?.Authorization||'');
      const body=JSON.parse(String(options.body||'{}'));
      const user=body.messages?.find(m=>m.role==='user')?.content||'';
      const marker='World snapshot:\n';
      const pos=user.lastIndexOf(marker);
      const snapshot=JSON.parse(user.slice(pos+marker.length));
      lastBatchSize=snapshot.agents.length;
      const decisions=snapshot.agents.map(a=>({
        agentId:a.agentId,
        action:{type:'WAIT',payload:{}},
        thought:`Agent ${a.agentId} snapshot thought`,
        goal:'observe',reason:'snapshot acceptance',plan:'wait',confidence:.8,replanAfterTicks:12
      }));
      await new Promise(r=>setTimeout(r,10));
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          usage:{prompt_tokens:100,completion_tokens:100,total_tokens:200},
          choices:[{message:{content:JSON.stringify({decisions})}}]
        })
      };
    };

    const testKey='test-key-not-secret-p611-123456789';
    window.AstraLifeWorldSnapshot.setKey(testKey);
    window.AstraLifeWorldSnapshot.enable();
    const provider=runtime.registry.get('world-snapshot-byok').adapter;
    const agents=runtime.state.agents.slice(0,60);
    const makeRequest=agent=>runtime.requestFactory.build(runtime.state,agent,runtime.observer.capture(runtime.state,agent),'world-snapshot-byok');
    const runAll=()=>Promise.all(agents.map(a=>provider.decide(makeRequest(a),{agent:a})));

    const first=await runAll();
    const status1=window.AstraLifeWorldSnapshot.status();
    check('bootstrapOneNetworkCallFor60Agents',fetchCount===1,{fetchCount});
    check('batchContains60Agents',lastBatchSize===60,{lastBatchSize});
    check('directTyphoonEndpoint',/api\.opentyphoon\.ai\/v1\/chat\/completions/.test(lastUrl),{lastUrl});
    check('browserSuppliesBearerKey',lastAuth===`Bearer ${testKey}`,{lastAuth:lastAuth?'<present>':''});
    check('all60Resolved',first.length===60&&first.every(r=>r.provider==='world-snapshot-byok'),{count:first.length});
    check('keyNotInLocalStorage',!JSON.stringify({...localStorage}).includes(testKey),{});
    check('keyNotInSessionStorage',!JSON.stringify({...sessionStorage}).includes(testKey),{});

    // Simulate accelerated world ticks: many ticks may pass, but wall-clock time
    // is still below the 30s periodic governor. No extra network call is allowed.
    for(let i=0;i<10;i++){
      runtime.state.tick++;
      fakeNow+=1000;
      const reused=await runAll();
      check(`acceleratedTick${i+1}Reuses`,reused.every(r=>r.diagnostics?.decisionSource==='snapshot-reuse'),{tick:runtime.state.tick});
    }
    const statusFast=window.AstraLifeWorldSnapshot.status();
    check('tenFastTicksDoNotAddNetworkCalls',fetchCount===1,{fetchCount,statusFast});
    check('reuseCounterRises',statusFast.stats.reuses>=600,{reuses:statusFast.stats.reuses});

    // Reach just under 30 seconds real time: still no periodic network call.
    fakeNow=1_029_999;
    runtime.state.tick++;
    await runAll();
    check('under30SecondsStillReuses',fetchCount===1,{fetchCount});

    // Cross 30 seconds real time: exactly one new snapshot for all 60 agents.
    fakeNow=1_030_001;
    runtime.state.tick++;
    const periodic=await runAll();
    const statusPeriodic=window.AstraLifeWorldSnapshot.status();
    check('periodicSnapshotAddsExactlyOneCall',fetchCount===2&&periodic.length===60,{fetchCount});
    check('periodicCounter',statusPeriodic.stats.periodicSnapshots===1,{stats:statusPeriodic.stats});

    // An action failure may wake the snapshot before the next 30s boundary,
    // but only after the 8s urgent cooldown.
    fakeNow+=8001;
    const a=agents[0];
    a.runtime.lastOutcome={actionId:'p611-fail-1',agentId:a.id,actionType:'WAIT',ok:false,message:'forced failure',significant:true};
    runtime.state.tick++;
    await runAll();
    const statusUrgent=window.AstraLifeWorldSnapshot.status();
    check('failureTriggersOneUrgentSnapshot',fetchCount===3,{fetchCount,statusUrgent});
    check('urgentCounter',statusUrgent.stats.urgentSnapshots>=1,{stats:statusUrgent.stats});
    check('rpmIsWindowedNotCumulative',statusUrgent.governor.rpm===3,{governor:statusUrgent.governor});
    check('totalNetworkCallsRemainSeparate',statusUrgent.stats.networkCalls===3,{stats:statusUrgent.stats});

    return {ok:failures.length===0,failures,fetchCount,lastBatchSize,status1,statusFast,statusPeriodic,statusUrgent,pageErrors:[]};
  });

  const relevantPageErrors=pageErrors.filter(e=>!e.includes('pickWalkFrame is not defined'));
  console.log(JSON.stringify({...result,relevantPageErrors,knownUnrelatedPageErrors:pageErrors.filter(e=>e.includes('pickWalkFrame is not defined'))},null,2));
  if(relevantPageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

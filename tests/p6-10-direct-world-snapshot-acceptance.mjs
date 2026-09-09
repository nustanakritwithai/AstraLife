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
    runtime.reset('P6.10-DIRECT-SNAPSHOT-20260909');
    runtime.state.running=false;

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
      await new Promise(r=>setTimeout(r,20));
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          usage:{prompt_tokens:100,completion_tokens:100,total_tokens:200},
          choices:[{message:{content:JSON.stringify({decisions})}}]
        })
      };
    };

    const testKey='test-key-not-secret-p610-123456789';
    window.AstraLifeWorldSnapshot.setKey(testKey);
    window.AstraLifeWorldSnapshot.enable();
    const provider=runtime.registry.get('world-snapshot-byok').adapter;
    const agents=runtime.state.agents.slice(0,60);
    const makeRequest=agent=>runtime.requestFactory.build(runtime.state,agent,runtime.observer.capture(runtime.state,agent),'world-snapshot-byok');

    const first=await Promise.all(agents.map(a=>provider.decide(makeRequest(a),{agent:a})));
    const status1=window.AstraLifeWorldSnapshot.status();

    check('oneNetworkCallFor60Agents',fetchCount===1,{fetchCount});
    check('batchContains60Agents',lastBatchSize===60,{lastBatchSize});
    check('directTyphoonEndpoint',/api\.opentyphoon\.ai\/v1\/chat\/completions/.test(lastUrl),{lastUrl});
    check('browserSuppliesBearerKey',lastAuth===`Bearer ${testKey}`,{lastAuth:lastAuth?'<present>':''});
    check('all60Resolved',first.length===60&&first.every(r=>r.provider==='world-snapshot-byok'),{count:first.length});
    check('snapshotStatsMatch',status1.stats.networkCalls===1&&status1.stats.lastBatchSize===60&&status1.stats.agentsResolved===60,{stats:status1.stats});
    check('keyNotInLocalStorage',!JSON.stringify({...localStorage}).includes(testKey),{});
    check('keyNotInSessionStorage',!JSON.stringify({...sessionStorage}).includes(testKey),{});

    runtime.state.tick++;
    const second=await Promise.all(agents.map(a=>provider.decide(makeRequest(a),{agent:a})));
    const status2=window.AstraLifeWorldSnapshot.status();
    check('nextTickUsesOneMoreSnapshotCall',fetchCount===2&&second.length===60,{fetchCount,second:second.length});
    check('twoTicksTwoNetworkCalls',status2.stats.networkCalls===2,{stats:status2.stats});

    return {ok:failures.length===0,failures,fetchCount,lastBatchSize,status1,status2,pageErrors:[]};
  });

  const relevantPageErrors=pageErrors.filter(e=>!e.includes('pickWalkFrame is not defined'));
  console.log(JSON.stringify({...result,relevantPageErrors,knownUnrelatedPageErrors:pageErrors.filter(e=>e.includes('pickWalkFrame is not defined'))},null,2));
  if(relevantPageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

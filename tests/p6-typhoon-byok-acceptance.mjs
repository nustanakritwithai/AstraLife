import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const pageErrors=[];
  const page=await browser.newPage();
  page.on('pageerror',error=>pageErrors.push(String(error?.stack||error)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeTyphoonBYOK);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6-BYOK-20260909');
    runtime.state.running=false;

    const fakeKey='test-key-memory-only-123456789';
    const configured=window.AstraLifeTyphoonBYOK.setKey(fakeKey);
    const status=window.AstraLifeTyphoonBYOK.status();
    const snapshot=runtime.snapshot();
    const serialized=JSON.stringify(snapshot);
    check('BYOK_keyConfiguredInMemory',configured===true&&status.configured===true,{configured,status});
    check('BYOK_keyNeverInSnapshot',!serialized.includes(fakeKey)&&snapshot.provider?.byok?.configured===true,{snapshotProvider:snapshot.provider});
    check('BYOK_passwordInputExists',document.getElementById('typhoonKeyInput')?.type==='password',{});

    const agent=runtime.state.agents[0];
    const observation=runtime.observer.capture(runtime.state,agent);
    const request=runtime.requestFactory.build(runtime.state,agent,observation,'typhoon-byok');
    const originalFetch=window.fetch;
    let authHeader=null,fetchCalls=0;
    window.fetch=async(_url,options={})=>{
      fetchCalls++;
      authHeader=options.headers?.authorization||options.headers?.Authorization||null;
      const decision={action:{type:'WAIT',payload:{}},goal:'observe',reason:'mock direct Typhoon decision',plan:'WAIT then observe',confidence:.72,replanAfterTicks:12};
      return new Response(JSON.stringify({model:'typhoon-v2.5-30b-a3b-instruct',choices:[{message:{content:JSON.stringify(decision)}}],usage:{total_tokens:33}}),{status:200,headers:{'content-type':'application/json'}});
    };

    let response=null,error=null;
    const provider=runtime.registry.get('typhoon-byok')?.adapter;
    try{response=await provider.decide(request)}catch(e){error=String(e?.message||e)}
    const validated=response?runtime.validator.validate(response,request,runtime.state):{ok:false,errors:[error]};
    check('BYOK_directTyphoonResponseValid',fetchCalls===1&&validated.ok===true&&response?.provider==='typhoon-byok',{fetchCalls,error,validated,response});
    check('BYOK_authorizationUsesMemoryKey',authHeader===`Bearer ${fakeKey}`,{hasAuth:!!authHeader});

    window.AstraLifeTyphoonBYOK.clearKey();
    const cleared=window.AstraLifeTyphoonBYOK.status();
    check('BYOK_clearRemovesKey',cleared.configured===false,{cleared});
    window.fetch=originalFetch;
    return {ok:failures.length===0,failures,version:window.AstraLifeTyphoonBYOK.version};
  });

  console.log(JSON.stringify({pageErrors,...result},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

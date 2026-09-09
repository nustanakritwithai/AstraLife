import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.stack||e)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeTyphoonQueue&&window.AstraLifeTyphoonBYOK&&window.AstraLifeLLMGate&&window.AstraColony);

  const result=await page.evaluate(async()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.5-INDEPENDENT-SESSIONS-20260909');
    runtime.state.running=false;

    let activeFetch=0,maxFetch=0,totalFetch=0;
    const perAgentCalls=new Map();
    const outboundByAgent=new Map();
    const maxMessagesByAgent=new Map();

    globalThis.fetch=async(_url,options={})=>{
      activeFetch++;totalFetch++;maxFetch=Math.max(maxFetch,activeFetch);
      const body=JSON.parse(String(options.body||'{}'));
      const messages=Array.isArray(body.messages)?body.messages:[];
      const currentUser=[...messages].reverse().find(m=>m.role==='user')?.content||'';
      const idMatch=currentUser.match(/\"agent\":\{\"id\":(\d+)/);
      const agentId=Number(idMatch?.[1]||0);
      const round=(perAgentCalls.get(agentId)||0)+1;
      perAgentCalls.set(agentId,round);
      if(!outboundByAgent.has(agentId))outboundByAgent.set(agentId,[]);
      outboundByAgent.get(agentId).push(messages.map(m=>({role:m.role,content:String(m.content)})));
      maxMessagesByAgent.set(agentId,Math.max(maxMessagesByAgent.get(agentId)||0,messages.length));

      await new Promise(r=>setTimeout(r,12));
      activeFetch--;
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          choices:[{message:{content:JSON.stringify({
            action:{type:'WAIT',payload:{}},thought:`PRIVATE_A${agentId}_R${round}`,goal:'observe',reason:`Agent ${agentId} needs more evidence`,plan:'wait and observe',confidence:.8,replanAfterTicks:12
          })}}]
        })
      };
    };

    window.AstraLifeTyphoonBYOK.setKey('test-key-not-secret-123456789');
    window.AstraLifeTyphoonBYOK.enable();
    const provider=runtime.registry.get('typhoon-byok').adapter;
    const agents=runtime.state.agents.slice(0,12);
    const makeRequest=agent=>{
      const obs=runtime.observer.capture(runtime.state,agent);
      return runtime.requestFactory.build(runtime.state,agent,obs,'typhoon-byok');
    };

    const firstRequests=agents.map(makeRequest);
    const promises=firstRequests.map((req,i)=>provider.decide(req,{agent:agents[i]}));
    await new Promise(r=>setTimeout(r,8));
    const queuedEarly=window.AstraLifeTyphoonQueue.status();
    const firstResponses=await Promise.all(promises);

    // Explicit replan triggers force real Typhoon turns so this legacy P6.5 test
    // still verifies independent multi-round provider histories under P6.6 gating.
    runtime.state.tick++;
    agents[0].mind.replanAtTick=runtime.state.tick;
    await provider.decide(makeRequest(agents[0]),{agent:agents[0]});
    runtime.state.tick++;
    agents[1].mind.replanAtTick=runtime.state.tick;
    await provider.decide(makeRequest(agents[1]),{agent:agents[1]});
    const a0=agents[0].id,a1=agents[1].id;
    const a0Second=outboundByAgent.get(a0)?.[1]||[];
    const a1Second=outboundByAgent.get(a1)?.[1]||[];
    const a0Text=a0Second.map(m=>m.content).join('\n');
    const a1Text=a1Second.map(m=>m.content).join('\n');

    // Drive one Agent through enough explicit replans to force a safe rollover.
    for(let i=0;i<20;i++){
      runtime.state.tick++;
      agents[0].mind.replanAtTick=runtime.state.tick;
      await provider.decide(makeRequest(agents[0]),{agent:agents[0]});
    }

    const final=window.AstraLifeTyphoonQueue.status();
    const s0=window.AstraLifeTyphoonBYOK.sessionStats(a0);
    const s1=window.AstraLifeTyphoonBYOK.sessionStats(a1);
    const allSessionIds=window.AstraLifeTyphoonBYOK.sessionAgentIds();

    check('allRequestsReachRealProvider',firstResponses.length===12&&firstResponses.every(r=>r.provider==='typhoon-byok'),{responses:firstResponses.length});
    check('browserConcurrencyIsBounded',maxFetch<=3,{maxFetch});
    check('excessRequestsQueueInsteadOfRejecting',queuedEarly.queueDepth>0&&queuedEarly.active<=3,{queuedEarly});
    check('queueFullyDrains',final.queueDepth===0&&final.active===0,{final});
    check('noQueueFailures',final.stats.failed===0,{final});
    check('apiWasActuallyCalled',totalFetch===34,{totalFetch});

    check('agent0CarriesOwnPreviousAssistantTurn',a0Text.includes(`PRIVATE_A${a0}_R1`),{a0Text:a0Text.slice(0,900)});
    check('agent0DoesNotContainAgent1PrivateTurn',!a0Text.includes(`PRIVATE_A${a1}_R1`),{a0Text:a0Text.slice(0,900)});
    check('agent1CarriesOwnPreviousAssistantTurn',a1Text.includes(`PRIVATE_A${a1}_R1`),{a1Text:a1Text.slice(0,900)});
    check('agent1DoesNotContainAgent0PrivateTurn',!a1Text.includes(`PRIVATE_A${a0}_R1`),{a1Text:a1Text.slice(0,900)});
    check('independentSessionsExist',allSessionIds.length>=12&&new Set(allSessionIds).size===allSessionIds.length,{allSessionIds});
    check('agentSessionsUseDifferentProviderSessionIds',s0?.sessionId&&s1?.sessionId&&s0.sessionId!==s1.sessionId,{s0,s1});
    check('longSessionRollsOverBeforeMessageCap',s0?.rollovers>=1&&s0.lastApiMessageCount<=44,{s0,maxMessages:maxMessagesByAgent.get(a0)});
    check('noApiCallExceeds44Messages',[...maxMessagesByAgent.values()].every(n=>n<=44),{maxMessagesByAgent:Object.fromEntries(maxMessagesByAgent)});
    check('otherAgentHistoryUnaffectedByAgent0Rollover',s1?.successfulTurns===2&&s1.rollovers===0,{s1});

    return {ok:failures.length===0,failures,maxFetch,totalFetch,queuedEarly,final,s0,s1,maxMessagesByAgent:Object.fromEntries(maxMessagesByAgent),pageErrors:[]};
  });
  console.log(JSON.stringify({...result,pageErrors},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

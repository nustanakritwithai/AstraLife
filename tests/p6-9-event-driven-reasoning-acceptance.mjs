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
    runtime.reset('P6.9-EVENT-DRIVEN-20260909');
    runtime.state.running=false;

    let totalFetch=0;
    const perAgentCalls=new Map();
    globalThis.fetch=async(_url,options={})=>{
      totalFetch++;
      const body=JSON.parse(String(options.body||'{}'));
      const latest=[...(body.messages||[])].reverse().find(m=>m.role==='user')?.content||'';
      const id=Number(latest.match(/\"agent\":\{\"id\":(\d+)/)?.[1]||0);
      const round=(perAgentCalls.get(id)||0)+1;
      perAgentCalls.set(id,round);
      await new Promise(r=>setTimeout(r,4));
      const action=id===runtime.state.agents[0].id && round===1
        ? {type:'SHARE',payload:{intent:'OFFER',facts:[],urgency:.3,text:'routine hello'}}
        : {type:'WAIT',payload:{}};
      return {
        ok:true,status:200,
        text:async()=>JSON.stringify({
          model:'typhoon-v2.5-30b-a3b-instruct',
          choices:[{message:{content:JSON.stringify({
            action,
            thought:`A${id} R${round}`,
            goal:'observe',reason:'event-driven test',plan:'continue current plan',confidence:.8,
            replanAfterTicks:1
          })}}]
        })
      };
    };

    window.AstraLifeTyphoonBYOK.setKey('test-key-not-secret-123456789');
    window.AstraLifeTyphoonBYOK.enable();
    const provider=runtime.registry.get('typhoon-byok').adapter;
    const agents=runtime.state.agents.slice(0,12);
    const makeRequest=agent=>runtime.requestFactory.build(runtime.state,agent,runtime.observer.capture(runtime.state,agent),'typhoon-byok');

    // Bootstrap: all Agents get one real LLM turn.
    const first=await Promise.all(agents.map(a=>provider.decide(makeRequest(a),{agent:a})));
    check('bootstrapUsesOneRealCallPerAgent',totalFetch===12&&first.length===12,{totalFetch});

    // Agent 0's first LLM action was SHARE. A successful routine SHARE must not
    // repeat the one-shot action and must not immediately call the LLM again.
    const shareAgent=agents[0];
    shareAgent.runtime.lastOutcome={actionId:'share-ok-1',agentId:shareAgent.id,actionType:'SHARE',ok:true,message:'routine share sent',significant:true};
    runtime.state.tick=1;
    const shareHold=await provider.decide(makeRequest(shareAgent),{agent:shareAgent});
    check('routineShareDoesNotFanOutIntoNewReasoning',totalFetch===12&&shareHold.decision?.action?.type==='WAIT'&&shareHold.diagnostics?.decisionSource==='cached-llm-one-shot-hold',{totalFetch,shareHold});

    // Eleven normal ticks: reusable plans keep running without any periodic
    // 6-9 tick herd refresh. The bootstrap floor is 12 ticks even though the
    // mocked model asks to replan after 1 tick.
    for(let tick=1;tick<=11;tick++){
      runtime.state.tick=tick;
      await Promise.all(agents.slice(1).map(a=>provider.decide(makeRequest(a),{agent:a})));
    }
    check('noPeriodicHerdRefreshBeforeTick12',totalFetch===12,{totalFetch});

    // Ordinary message must enter Memory/context but not force a real call.
    runtime.state.tick=5;
    const normalReq=JSON.parse(JSON.stringify(makeRequest(agents[1])));
    normalReq.observation.messages=[{id:9001,from:99,to:agents[1].id,intent:'REPORT',tick:5,urgency:.4,text:'routine report',replyTo:null,facts:[]}];
    const beforeNormalMessage=totalFetch;
    await provider.decide(normalReq,{agent:agents[1]});
    check('ordinaryMessageDoesNotCallLlm',totalFetch===beforeNormalMessage,{totalFetch,beforeNormalMessage});

    // New facts alone must not force a call.
    const factReq=JSON.parse(JSON.stringify(makeRequest(agents[2])));
    factReq.memory.newFactKeys=['resource:test'];
    const beforeFact=totalFetch;
    await provider.decide(factReq,{agent:agents[2]});
    check('newFactDoesNotCallLlmImmediately',totalFetch===beforeFact,{totalFetch,beforeFact});

    // Tick 12 reaches the event-driven scheduled floor and all background
    // sessions may reason again. This is ~37.5 baseline calls/min for 60 Agents,
    // versus ~60/min from the old 6-9 tick refresh before other events.
    runtime.state.tick=12;
    await Promise.all(agents.map(a=>provider.decide(makeRequest(a),{agent:a})));
    check('scheduledReplanOccursAtTick12',totalFetch===24,{totalFetch});

    // Urgent message wakes exactly the affected Agent immediately.
    runtime.state.tick=13;
    const urgentReq=JSON.parse(JSON.stringify(makeRequest(agents[3])));
    urgentReq.observation.messages=[{id:9002,from:98,to:agents[3].id,intent:'WARN',tick:13,urgency:.95,text:'danger',replyTo:null,facts:[]}];
    const beforeUrgent=totalFetch;
    await provider.decide(urgentReq,{agent:agents[3]});
    check('urgentMessageCallsLlmImmediately',totalFetch===beforeUrgent+1,{totalFetch,beforeUrgent});

    // Action failure also wakes exactly the affected Agent.
    runtime.state.tick=14;
    const failed=agents[4];
    failed.runtime.lastOutcome={actionId:'fail-1',agentId:failed.id,actionType:'MOVE',ok:false,message:'blocked',significant:true};
    const beforeFailure=totalFetch;
    await provider.decide(makeRequest(failed),{agent:failed});
    check('actionFailureCallsLlmImmediately',totalFetch===beforeFailure+1,{totalFetch,beforeFailure});

    const gate=window.AstraLifeLLMGate.status();
    const dispatcher=window.AstraLifeTyphoonQueue.status();
    check('eventDrivenPolicyActive',window.AstraLifeLLMGate.version==='p6.9-event-driven-reasoning'&&window.AstraLifeLLMGate.policy?.ignoredImmediateTriggers?.includes('periodic-max-stale'),{version:window.AstraLifeLLMGate.version,policy:window.AstraLifeLLMGate.policy});
    check('backgroundFloorIs12Ticks',gate.limits?.backgroundMinReplanTicks===12,{limits:gate.limits});
    check('fullThroughputCapacityPreserved',dispatcher.limits?.maxActiveTotal===48,{limits:dispatcher.limits});
    check('sessionsRemainIndependent',Number(dispatcher.upstream?.sessions?.count||0)>=12,{sessions:dispatcher.upstream?.sessions});
    check('noProviderFailures',Number(dispatcher.stats?.failed||0)===0,{stats:dispatcher.stats});

    return {ok:failures.length===0,failures,totalFetch,gate,dispatcher,pageErrors:[]};
  });

  const knownUnrelatedPageErrors=pageErrors.filter(e=>/pickWalkFrame is not defined/.test(e));
  const relevantPageErrors=pageErrors.filter(e=>!/pickWalkFrame is not defined/.test(e));
  console.log(JSON.stringify({...result,relevantPageErrors,knownUnrelatedPageErrors},null,2));
  if(relevantPageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

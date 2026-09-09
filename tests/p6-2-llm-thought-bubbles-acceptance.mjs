import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless:true });
try{
  const pageErrors=[];
  const page=await browser.newPage();
  page.on('pageerror',error=>pageErrors.push(String(error?.stack||error)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeLLMThoughtBubbles&&window.AstraLifeTurnAhead&&window.AstraLifeFramePacing);

  const result=await page.evaluate(()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.4-natural-thought-bubbles-20260909');
    runtime.state.running=false;

    const api=window.AstraLifeLLMThoughtBubbles;
    const agent=runtime.state.agents[0];
    const observation=runtime.observer.capture(runtime.state,agent);
    const request=runtime.requestFactory.build(runtime.state,agent,observation,'typhoon-byok');
    const naturalThought='I should check that water source before moving farther.';
    const response={
      protocol:PROTOCOL.decisionResponse,
      requestId:request.requestId,
      agentId:agent.id,
      tick:request.simulation.tick,
      provider:'typhoon-byok',
      decision:{
        action:{protocol:PROTOCOL.action,type:ACTION.MOVE,payload:{x:runtime.state.camp.x+12,y:runtime.state.camp.y+8,speed:.8}},
        cognition:{goal:'find water',reason:'camp water is low',plan:'move toward a visible water source',thought:naturalThought},
        thought:naturalThought,
        reason:'camp water is low',confidence:.82,replanAfterTicks:12
      },
      diagnostics:{
        chain_of_thought:'SECRET_COT_MARKER',
        deliberation:['SECRET_DELIBERATION_MARKER']
      }
    };

    const extracted=api.extractForTest(response);
    check('explicitNaturalThoughtWins',extracted?.text===naturalThought,{extracted});
    check('statusCompositionRemoved',!extracted?.text.includes(' · MOVE')&&!extracted?.text.startsWith('find water ·'),{extracted});
    check('hiddenReasoningNeverIncluded',!JSON.stringify(extracted).includes('SECRET_COT_MARKER')&&!JSON.stringify(extracted).includes('SECRET_DELIBERATION_MARKER'),{extracted});

    const noThought=JSON.parse(JSON.stringify(response));
    delete noThought.decision.thought;
    delete noThought.decision.cognition.thought;
    noThought.requestId=`${request.requestId}:fallback`;
    const fallback=api.extractForTest(noThought);
    check('naturalProviderReasonFallback',fallback?.text==='camp water is low',{fallback});
    check('fallbackStillNotStatusComposition',!fallback?.text.includes('MOVE')&&!fallback?.text.includes('find water ·'),{fallback});

    const local={...response,provider:'local',requestId:`${request.requestId}:local`};
    check('localProviderDoesNotCreateLlmBubble',api.extractForTest(local)===null,{localExtract:api.extractForTest(local)});

    runtime.decisionRouter.ready.set(agent.id,{request,response,providerId:'typhoon-byok',latencyMs:42});
    render(true);
    const staged=api.getThought(agent.id);
    const visible=api.visibleAgentIds();
    check('stagedNaturalThoughtVisibleBeforeExecution',staged?.staged===true&&staged.text===naturalThought&&visible.includes(agent.id),{staged,visible});

    runtime.selectedAgentId=agent.id;
    const renderResult=render(true);
    check('renderOverlayPreservesRenderContract',renderResult===true,{renderResult});

    const longResponse=JSON.parse(JSON.stringify(response));
    longResponse.requestId=`${request.requestId}:long`;
    longResponse.decision.cognition.thought='t'.repeat(300);
    longResponse.decision.thought='t'.repeat(300);
    const longExtract=api.extractForTest(longResponse);
    check('naturalThoughtIsBounded',longExtract?.text.length<=140,{longExtract});

    return {ok:failures.length===0,failures,pageErrors:[],version:api.version,policy:api.policy,limits:api.limits,staged,visible};
  });

  console.log(JSON.stringify({...result,pageErrors},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{
  await browser.close();
}

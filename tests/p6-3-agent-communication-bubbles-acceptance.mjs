import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const pageErrors=[];
  const page=await browser.newPage();
  page.on('pageerror',error=>pageErrors.push(String(error?.stack||error)));
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeCommunicationBubbles&&window.AstraLifeLLMThoughtBubbles&&window.AstraLifeTurnAhead);

  const result=await page.evaluate(()=>{
    const failures=[];
    const check=(name,condition,detail={})=>{if(!condition)failures.push({name,detail})};
    runtime.state.running=false;
    runtime.reset('P6.3-communication-bubbles-20260909');
    runtime.state.running=false;

    const [speaker,target,peer]=runtime.state.agents.slice(0,3);
    speaker.body.x=runtime.state.camp.x;speaker.body.y=runtime.state.camp.y;
    target.body.x=speaker.body.x+12;target.body.y=speaker.body.y;
    peer.body.x=speaker.body.x+18;peer.body.y=speaker.body.y+3;

    const targeted={
      id:900001,tick:runtime.state.tick,agentId:speaker.id,type:ACTION.SHARE,
      payload:{intent:'REQUEST_HELP',targetAgentId:target.id,replyTo:null,urgency:.9,text:'Need help at camp',facts:[]},
      reason:'P6.3 targeted test',priority:PRIORITY.SHARE,meta:{validated:true,provider:'typhoon-byok'}
    };
    const targetedOutcome=runtime.resolver.resolve(runtime.state,[targeted])[0];
    const targetedBubble=window.AstraLifeCommunicationBubbles.getSpeech(speaker.id);
    const receiverBubble=window.AstraLifeCommunicationBubbles.getSpeech(target.id);
    check('targetedShareResolved',targetedOutcome?.ok===true&&targetedOutcome.recipients?.length===1&&targetedOutcome.recipients[0]===target.id,{targetedOutcome});
    check('speakerGetsSpeechBubble',targetedBubble?.intent==='REQUEST_HELP'&&targetedBubble?.text==='Need help at camp'&&targetedBubble?.target===target.name,{targetedBubble,targetName:target.name});
    check('receiverDoesNotFakeReply',receiverBubble===null,{receiverBubble});

    const fact={key:'resource:4242',value:{id:4242,type:'water',x:speaker.body.x+20,y:speaker.body.y+5},confidence:.88};
    const broadcast={
      id:900002,tick:runtime.state.tick,agentId:speaker.id,type:ACTION.SHARE,
      payload:{intent:'REPORT',targetAgentId:null,replyTo:null,urgency:.6,text:'',facts:[fact]},
      reason:'P6.3 broadcast test',priority:PRIORITY.SHARE,meta:{validated:true,provider:'typhoon-byok'}
    };
    const broadcastOutcome=runtime.resolver.resolve(runtime.state,[broadcast])[0];
    const broadcastBubble=window.AstraLifeCommunicationBubbles.getSpeech(speaker.id);
    check('broadcastShareResolved',broadcastOutcome?.ok===true&&broadcastOutcome.recipients?.length>=2,{broadcastOutcome});
    check('factFallbackProducesReadableSpeech',broadcastBubble?.intent==='REPORT'&&/water #4242/i.test(broadcastBubble?.text||'')&&/agents$/.test(broadcastBubble?.target||''),{broadcastBubble});

    const invalid={
      id:900003,tick:runtime.state.tick,agentId:peer.id,type:ACTION.SHARE,
      payload:{intent:'REPORT',targetAgentId:target.id,replyTo:null,urgency:.5,text:'fake',facts:[]},
      reason:'invalid report',priority:PRIORITY.SHARE,meta:{validated:true,provider:'typhoon-byok'}
    };
    const invalidOutcome=runtime.resolver.resolve(runtime.state,[invalid])[0];
    const invalidBubble=window.AstraLifeCommunicationBubbles.getSpeech(peer.id);
    check('rejectedShareCreatesNoSpeechBubble',invalidOutcome?.ok===false&&invalidBubble===null,{invalidOutcome,invalidBubble});

    const visible=window.AstraLifeCommunicationBubbles.activeSpeakerIds();
    const rendered=render(true);
    check('speakerIsVisible',visible.includes(speaker.id),{visible,speakerId:speaker.id});
    check('renderContractPreserved',rendered===true,{rendered});
    check('policyDoesNotFabricateReceiverSpeech',/no fabricated receiver speech/i.test(window.AstraLifeCommunicationBubbles.policy||''),{policy:window.AstraLifeCommunicationBubbles.policy});
    check('limitsBoundVisibleSpeech',window.AstraLifeCommunicationBubbles.limits.maxVisible<=10&&window.AstraLifeCommunicationBubbles.limits.activeMs<=8000,{limits:window.AstraLifeCommunicationBubbles.limits});

    return {ok:failures.length===0,failures,targetedOutcome,targetedBubble,broadcastOutcome,broadcastBubble,visible,version:window.AstraLifeCommunicationBubbles.version};
  });

  console.log(JSON.stringify({pageErrors,...result},null,2));
  if(pageErrors.length||!result.ok)process.exitCode=1;
}finally{await browser.close()}

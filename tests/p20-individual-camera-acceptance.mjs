import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1,isMobile:true,hasTouch:true});
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraColony&&window.AstraLifeCamera);
  const result=await page.evaluate(()=>{
    runtime.state.running=false;
    AstraColony.reset('P20-INDIVIDUAL-CAMERA-20260907');
    runtime.state.running=false;
    const camera=window.AstraLifeCamera;
    const living=runtime.state.agents.filter(agent=>agent.alive);
    const first=living[0],second=living[1];
    const initial=camera.getState();
    const firstPosition={x:first.body.x,y:first.body.y};
    const initialSnapshot=JSON.stringify(runtime.snapshot());
    const firstScreen=camera.worldToScreen(firstPosition);
    const firstRoundTrip=camera.screenToWorld(firstScreen.x,firstScreen.y);
    const focusResult=camera.focusAgent(second.id);
    const focused=camera.getState();
    const focusedScreen=camera.worldToScreen({x:second.body.x,y:second.body.y});
    const focusedRoundTrip=camera.screenToWorld(focusedScreen.x,focusedScreen.y);
    const afterFocusSnapshot=JSON.stringify(runtime.snapshot());
    camera.fitToMap();
    const fitState=camera.getState();
    const corners=[[0,0],[SPACE.width,0],[0,SPACE.height],[SPACE.width,SPACE.height]].map(([x,y])=>camera.worldToScreen({x,y}));
    camera.focusAgent(second.id);
    const thought1=camera.getFocusedThought();
    const beforeThoughtState=JSON.stringify(runtime.snapshot());
    const original={goal:second.mind.goal,goalReason:second.mind.goalReason,plan:second.mind.plan,lastActionType:second.runtime.lastActionType};
    second.mind.goal='protect_camp';second.mind.goalReason='storm warning received';second.mind.plan='MOVE → BUILD';second.runtime.lastActionType=ACTION.BUILD;
    const thought2=camera.getFocusedThought();render(true);
    second.mind.goal=original.goal;second.mind.goalReason=original.goalReason;second.mind.plan=original.plan;second.runtime.lastActionType=original.lastActionType;
    const restoredThoughtState=JSON.stringify(runtime.snapshot());
    const eps=.001;
    const closeTo=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y)<eps;
    const cornersFit=corners.every(p=>p.x>=-1&&p.x<=CSS_W+1&&p.y>=-1&&p.y<=CSS_H+1);
    const tests={
      defaultSelectsLivingAgent:initial.selectedAgentId===first.id&&initial.focusedAgentId===first.id,
      defaultIsCloseView:initial.zoom>initial.fitZoom&&Math.abs(initial.center.x-firstPosition.x)<2&&Math.abs(initial.center.y-firstPosition.y)<2,
      focusMovesToSelectedAgent:focusResult?.id===second.id&&focused.selectedAgentId===second.id&&Math.abs(focused.center.x-second.body.x)<2&&Math.abs(focused.center.y-second.body.y)<2,
      screenWorldInvariantAtDefault:closeTo(firstRoundTrip,firstPosition),
      screenWorldInvariantAfterFocus:closeTo(focusedRoundTrip,{x:second.body.x,y:second.body.y}),
      zoomOutFitsWholeMap:Math.abs(fitState.zoom-fitState.fitZoom)<eps&&cornersFit,
      cameraDoesNotMutateWorldState:initialSnapshot===afterFocusSnapshot&&beforeThoughtState===restoredThoughtState,
      thoughtTracksCognitiveState:thought1.agentId===second.id&&thought1.text!==thought2.text&&thought2.text.includes('protect camp')&&thought2.text.includes('BUILD')
    };
    return {ok:Object.values(tests).every(Boolean),tests,initial,focused,fitState,thought1,thought2,corners};
  });
  console.log(JSON.stringify(result,null,2));
  if(!result.ok)process.exitCode=1;
}finally{await browser.close()}

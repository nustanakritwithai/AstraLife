(() => {
  "use strict";

  const PACING = Object.freeze({
    intervalMs:8000,
    simulationTicksPerSecond:0.125,
    maxElapsedMs:100,
    maxTicksPerFrame:2,
    maxBacklogTicks:6
  });
  const WALK_FRAME_MS = 620;
  const WALK_BOB_DIVISOR = 340;
  const WALK_BOB_AMPLITUDE = 0.42;

  visualAlpha = function(){
    return clamp(visualElapsedMs/PACING.intervalMs,0,1);
  };

  visualDiagnostics = function(){
    return {
      alpha:visualAlpha(),
      intervalMs:PACING.intervalMs,
      previousTick:visualPrevious?visualPrevious.tick:null,
      nextTick:visualNext?visualNext.tick:null,
      visualElapsedMs,
      stateTick:runtime.state.tick
    };
  };

  advanceSimulation = function(elapsedMs,{ignoreRunning=false}={}){
    const elapsed=Math.min(PACING.maxElapsedMs,Math.max(0,Number(elapsedMs)||0));
    frameStats.lastElapsedMs=elapsed;
    if(!runtime.state.running&&!ignoreRunning){tickBudget=0;return 0}
    const scaledElapsed=elapsed*runtime.state.speed;
    const requested=tickBudget+scaledElapsed/PACING.intervalMs;
    visualElapsedMs+=scaledElapsed;
    if(requested>PACING.maxBacklogTicks)frameStats.droppedTicks+=requested-PACING.maxBacklogTicks;
    tickBudget=Math.min(PACING.maxBacklogTicks,requested);
    const ticks=Math.min(Math.floor(tickBudget+1e-9),PACING.maxTicksPerFrame);
    for(let i=0;i<ticks;i++){
      const previous=captureVisualSnapshot(runtime.state);
      runtime.tickOnce();
      const next=captureVisualSnapshot(runtime.state);
      rememberAuthoritativeTick(previous,next);
      visualElapsedMs=Math.max(0,visualElapsedMs-PACING.intervalMs);
    }
    if(ticks===0)visualElapsedMs=Math.min(visualElapsedMs,PACING.intervalMs);
    tickBudget-=ticks;
    frameStats.frames++;frameStats.totalTicks+=ticks;
    frameStats.maxTicksPerFrame=Math.max(frameStats.maxTicksPerFrame,ticks);
    frameStats.maxBacklogTicks=Math.max(frameStats.maxBacklogTicks,tickBudget);
    return ticks;
  };

  pickWalkFrame = function(role){
    const frames=agentWalkSprites[role]||[];
    const idx=Math.floor(performance.now()/WALK_FRAME_MS)%AGENT_WALK_FRAMES;
    const walk=frames[idx];
    if(walk&&walk.complete&&walk.naturalWidth>0)return walk;
    for(const f of frames){if(f&&f.complete&&f.naturalWidth>0)return f}
    return null;
  };

  drawAgent = function(a,selected){
    const p=visualAgentPosition(a),x=p.x,y=p.y;
    if(!a.alive){ctx.fillStyle="#3c4741";ctx.fillRect(x-2,y-2,4,4);return}
    const motion=agentMotion(a,x,y);
    const facing=agentFacing.get(a.id)||1;
    const size=selected?22:18;
    let sprite=null;
    if(motion.moving)sprite=pickWalkFrame(a.role);
    if(!sprite){
      const idle=agentSprites[a.role];
      if(idle&&idle.complete&&idle.naturalWidth>0)sprite=idle;
    }
    if(sprite){
      const bob=motion.moving?Math.sin(performance.now()/WALK_BOB_DIVISOR)*WALK_BOB_AMPLITUDE:0;
      ctx.save();
      ctx.translate(x,y-1+bob);
      ctx.scale(facing,1);
      ctx.drawImage(sprite,-size/2,-size/2,size,size);
      ctx.restore();
    }else{
      ctx.fillStyle=ROLE_COLORS[a.role]||"#77f2ad";ctx.beginPath();ctx.arc(x,y,selected?5.5:3.5,0,Math.PI*2);ctx.fill();
    }
    if(a.runtime.lastProvider&&a.runtime.lastProvider!=="local"){
      ctx.strokeStyle=PROVIDER_RING[a.runtime.lastProvider]||"#d393ff";ctx.lineWidth=a.runtime.providerStatus==="pending"?1.8:.8;
      ctx.beginPath();ctx.arc(x,y,a.runtime.providerStatus==="pending"?12:10,0,Math.PI*2);ctx.stroke();
    }
    if(a.body.hp<45){ctx.strokeStyle="#ff7b7b";ctx.lineWidth=1.2;ctx.beginPath();ctx.arc(x,y,11,0,Math.PI*2);ctx.stroke()}
    if(a.inventory.amount>0){ctx.fillStyle=a.inventory.type==="water"?"#55b5ff":a.inventory.type==="food"?"#df73ff":"#b7804b";ctx.fillRect(x-2.5,y+size/2-1,5,2)}
    if(selected){
      ctx.strokeStyle="#fff";ctx.lineWidth=1;ctx.beginPath();ctx.arc(x,y,13,0,Math.PI*2);ctx.stroke();
      ctx.fillStyle="#fff";ctx.font="10px system-ui";ctx.fillText(a.name,x+14,y-8);
      if(a.mind.target){ctx.strokeStyle="#fff6";ctx.setLineDash([4,4]);ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(a.mind.target.x,a.mind.target.y);ctx.stroke();ctx.setLineDash([])}
    }
  };

  window.AstraLifeFramePacing = Object.freeze({
    config:PACING,
    animation:Object.freeze({walkFrameMs:WALK_FRAME_MS,bobDivisor:WALK_BOB_DIVISOR,bobAmplitude:WALK_BOB_AMPLITUDE}),
    getStats:()=>({...frameStats,backlogTicks:tickBudget}),
    getVisualState:()=>visualDiagnostics(),
    getInterpolatedAgentPosition:agentId=>{const agent=runtime.state.agentById.get(Number(agentId));return agent?visualAgentPosition(agent):null},
    reset:()=>{resetFramePacing();resetVisualInterpolation();return {...frameStats,backlogTicks:tickBudget}},
    advanceForTest:elapsedMs=>{const ticks=advanceSimulation(elapsedMs,{ignoreRunning:true});return {ticks,...frameStats,backlogTicks:tickBudget,visual:visualDiagnostics()}}
  });
})();

const CAMERA_CONFIG=Object.freeze({defaultZoomMultiplier:2.8,minZoomPadding:1,maxZoom:3.5,focusEasing:.22});
const camera={center:{x:SPACE.width/2,y:SPACE.height/2},zoom:1,followSelected:true,initialized:false};
let cameraSnapPending=false;

function fitZoom(){return Math.min(CSS_W/SPACE.width,CSS_H/SPACE.height)}
function defaultCloseZoom(){return clamp(Math.max(fitZoom()*CAMERA_CONFIG.defaultZoomMultiplier,CAMERA_CONFIG.minZoomPadding),fitZoom(),CAMERA_CONFIG.maxZoom)}
function cameraBounds(zoom=camera.zoom){
  const width=Math.min(SPACE.width,CSS_W/zoom),height=Math.min(SPACE.height,CSS_H/zoom);
  return {halfWidth:Math.min(SPACE.width/2,width/2),halfHeight:Math.min(SPACE.height/2,height/2),width,height};
}
function clampCameraCenter(center,zoom=camera.zoom){
  const b=cameraBounds(zoom);
  return {x:clamp(center.x,b.halfWidth,SPACE.width-b.halfWidth),y:clamp(center.y,b.halfHeight,SPACE.height-b.halfHeight)};
}
function livingAgent(id=runtime.selectedAgentId){
  const selected=id?runtime.state.agentById.get(Number(id)):null;
  return selected?.alive?selected:runtime.state.agents.find(agent=>agent.alive)||null;
}
function worldView(){
  const scale=camera.zoom;
  const width=SPACE.width*scale,height=SPACE.height*scale;
  return {scale,zoom:scale,fitZoom:fitZoom(),ox:CSS_W/2-camera.center.x*scale,oy:CSS_H/2-camera.center.y*scale,width,height,center:{...camera.center}};
}
function worldToScreen(point){
  const v=worldView();return {x:point.x*v.scale+v.ox,y:point.y*v.scale+v.oy};
}
function screenToWorld(clientX,clientY){
  const r=canvas.getBoundingClientRect(),v=worldView();
  return {x:(clientX-r.left-v.ox)/v.scale,y:(clientY-r.top-v.oy)/v.scale};
}
function screenPoint(clientX,clientY){
  const r=canvas.getBoundingClientRect();return {x:clientX-r.left,y:clientY-r.top};
}
function screenLocalToWorld(x,y){
  const v=worldView();return {x:(x-v.ox)/v.scale,y:(y-v.oy)/v.scale};
}
function ensureCameraTarget(){
  const target=livingAgent();
  if(target&&!runtime.selectedAgentId)runtime.selectedAgentId=target.id;
  if(!camera.initialized){
    camera.zoom=defaultCloseZoom();camera.center=clampCameraCenter(target?{x:target.body.x,y:target.body.y}:{x:SPACE.width/2,y:SPACE.height/2});camera.followSelected=true;camera.initialized=true;
  }
  return target;
}
function focusCamera(id=runtime.selectedAgentId){
  const target=livingAgent(id);if(!target)return null;
  runtime.selectedAgentId=target.id;camera.followSelected=true;camera.center=clampCameraCenter({x:visualAgentPosition(target).x,y:visualAgentPosition(target).y});cameraSnapPending=true;return target;
}
function resetCameraToDefault(){
  const target=livingAgent();if(target)runtime.selectedAgentId=target.id;
  camera.zoom=defaultCloseZoom();camera.followSelected=true;camera.center=clampCameraCenter(target?{x:target.body.x,y:target.body.y}:{x:SPACE.width/2,y:SPACE.height/2});camera.initialized=true;cameraSnapPending=true;
  return target;
}
function fitCameraToMap(){
  camera.zoom=fitZoom();camera.center={x:SPACE.width/2,y:SPACE.height/2};camera.followSelected=false;camera.initialized=true;return worldView();
}
function zoomCameraAt(nextZoom,localX=CSS_W/2,localY=CSS_H/2){
  const before=screenLocalToWorld(localX,localY),zoom=clamp(Number(nextZoom)||camera.zoom,fitZoom(),CAMERA_CONFIG.maxZoom);
  camera.zoom=zoom;camera.center=clampCameraCenter({x:before.x-(localX-CSS_W/2)/zoom,y:before.y-(localY-CSS_H/2)/zoom},zoom);camera.initialized=true;return worldView();
}
function zoomCameraBy(factor,localX=CSS_W/2,localY=CSS_H/2){return zoomCameraAt(camera.zoom*factor,localX,localY)}
function syncCameraToSelected(){
  const target=ensureCameraTarget();if(!target||!camera.followSelected)return target;
  const p=visualAgentPosition(target),next=clampCameraCenter(p);
  camera.center=cameraSnapPending?next:{x:camera.center.x+(next.x-camera.center.x)*CAMERA_CONFIG.focusEasing,y:camera.center.y+(next.y-camera.center.y)*CAMERA_CONFIG.focusEasing};
  cameraSnapPending=false;
  return target;
}
function terrainColor(type,night){
  const palette=night?{forest:"#0c2216",meadow:"#102a1b",rock:"#17231d",wetland:"#0b2421"}:{forest:"#174229",meadow:"#1b4c2d",rock:"#30423a",wetland:"#164641"};
  return palette[type]||palette.meadow;
}
function drawBackground(state){
  const phase=(state.tick%CONFIG.dayTicks)/CONFIG.dayTicks;const night=phase>.68||phase<.08;
  ctx.fillStyle=night?"#06100c":"#10271b";ctx.fillRect(0,0,SPACE.width,SPACE.height);
  ctx.globalAlpha=.43;
  for(const p of state.terrain){ctx.fillStyle=terrainColor(p.type,night);ctx.beginPath();ctx.arc(p.x,p.y,p.r,0,Math.PI*2);ctx.fill()}
  ctx.globalAlpha=1;
  if(state.stormTicks>0){ctx.fillStyle="#7899b824";ctx.fillRect(0,0,SPACE.width,SPACE.height);ctx.strokeStyle="#cde8ff25";for(let i=0;i<14;i++){const x=(state.tick*17+i*97)%SPACE.width;ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x-120,SPACE.height);ctx.stroke()}}
}
function drawResource(r){
  if(r.amount<=.05)return;const ratio=clamp(r.amount/r.max,0,1);
  if(r.type==="water"){
    ctx.fillStyle=RESOURCE_COLORS.water;ctx.beginPath();ctx.ellipse(r.x,r.y,7+ratio*7,4+ratio*4,0,0,Math.PI*2);ctx.fill();ctx.strokeStyle="#b9e5ff88";ctx.stroke();
  }else if(r.type==="berry"){
    ctx.fillStyle=RESOURCE_COLORS.berry;ctx.beginPath();ctx.arc(r.x,r.y,3.5+ratio*1.7,0,Math.PI*2);ctx.fill();
  }else if(r.type==="tree"){
    ctx.fillStyle="#76502e";ctx.fillRect(r.x-2,r.y-1,4,9);ctx.fillStyle=RESOURCE_COLORS.tree;ctx.beginPath();ctx.arc(r.x,r.y-6,5+ratio*3,0,Math.PI*2);ctx.fill();
  }else{
    ctx.fillStyle=RESOURCE_COLORS.herb;ctx.beginPath();ctx.arc(r.x,r.y,2.8+ratio,0,Math.PI*2);ctx.fill();
  }
}
function drawCamp(state){
  const c=state.camp;
  ctx.strokeStyle="#ffd36a99";ctx.lineWidth=1.5;ctx.beginPath();ctx.arc(c.x,c.y,c.r+c.shelter*2,0,Math.PI*2);ctx.stroke();
  ctx.fillStyle="#ffd36a";ctx.beginPath();ctx.arc(c.x,c.y,7,0,Math.PI*2);ctx.fill();
  ctx.fillStyle="#fff0ae";ctx.font="10px system-ui";ctx.fillText("CAMP",c.x+12,c.y+3);
  for(let i=0;i<c.shelter;i++){
    const angle=i/Math.max(c.shelter,1)*Math.PI*2;const x=c.x+Math.cos(angle)*35,y=c.y+Math.sin(angle)*35;
    ctx.fillStyle="#9b713f";ctx.fillRect(x-5,y-4,10,8);ctx.fillStyle="#d9ad6c";ctx.beginPath();ctx.moveTo(x-7,y-4);ctx.lineTo(x,y-10);ctx.lineTo(x+7,y-4);ctx.fill();
  }
  if(c.construction.active){
    const p=clamp(c.construction.progress/CONFIG.buildRequiredProgress,0,1);
    ctx.fillStyle="#06100cbb";ctx.fillRect(c.x-35,c.y+48,70,7);ctx.fillStyle="#ffd36a";ctx.fillRect(c.x-34,c.y+49,68*p,5);
  }
}
function drawMessageEffects(state){
  for(const e of state.effects.messages){
    const a=state.agentById.get(e.fromId),b=state.agentById.get(e.toId);if(!a||!b||!a.alive||!b.alive)continue;
    const alpha=clamp(1-(state.tick-e.bornTick)/15,0,1)*.48;const rgb=e.intent==="WARN"?"255,139,139":e.intent==="REQUEST_HELP"?"255,211,106":e.intent==="ASK"?"117,201,255":e.intent==="OFFER"?"211,147,255":"126,225,177";ctx.strokeStyle=`rgba(${rgb},${alpha})`;ctx.lineWidth=e.intent==="WARN"?1.25:.75;
    ctx.beginPath();const pa=visualAgentPosition(a),pb=visualAgentPosition(b);ctx.moveTo(pa.x,pa.y);ctx.lineTo(pb.x,pb.y);ctx.stroke();
  }
}
const AGENT_SPRITE_ROLES=["generalist","scout","gatherer","builder","healer","carrier","coordinator"];
const AGENT_WALK_FRAMES=4;
const agentSprites=Object.create(null);
const agentWalkSprites=Object.create(null);
const agentFacing=new Map();
(function loadAgentSprites(){
  for(const role of AGENT_SPRITE_ROLES){
    const idle=new Image();
    idle.decoding="async";
    idle.src=`assets/sprites/chibi/${role}.png`;
    agentSprites[role]=idle;
    const walks=[];
    for(let i=0;i<AGENT_WALK_FRAMES;i++){
      const img=new Image();
      img.decoding="async";
      img.src=`assets/sprites/chibi/walk/${role}/f${i}.png`;
      walks.push(img);
    }
    agentWalkSprites[role]=walks;
  }
})();
function agentMotion(a){
  const current={x:a.body.x,y:a.body.y};
  const from=(typeof visualPrevious!=="undefined"&&visualPrevious&&visualPrevious.agents.get(a.id))||current;
  const to=(typeof visualNext!=="undefined"&&visualNext&&visualNext.agents.get(a.id))||current;
  const dx=to.x-from.x,dy=to.y-from.y;
  const dist=Math.hypot(dx,dy);
  const moving=dist>0.35||a.runtime?.lastActionType===ACTION.MOVE;
  if(Math.abs(dx)>0.08)agentFacing.set(a.id,dx>=0?1:-1);
  else if(a.mind?.target){
    const tdx=a.mind.target.x-a.body.x;
    if(Math.abs(tdx)>0.5)agentFacing.set(a.id,tdx>=0?1:-1);
  }
  return {moving,dx,dy,dist};
}
function drawAgent(a,selected){
  const p=visualAgentPosition(a),x=p.x,y=p.y;
  if(!a.alive){ctx.fillStyle="#3c4741";ctx.fillRect(x-2,y-2,4,4);return}
  const motion=agentMotion(a);
  const facing=agentFacing.get(a.id)||1;
  const size=selected?18:14;
  let sprite=agentSprites[a.role];
  if(motion.moving){
    const frames=agentWalkSprites[a.role]||[];
    const speed=Math.max(1,Number(runtime.state?.speed)||1);
    const interval=(typeof FRAME_PACING!=="undefined"&&FRAME_PACING.intervalMs)||2000;
    const phase=(typeof visualElapsedMs==="number"?visualElapsedMs:0)+((runtime.state?.tick||0)*interval);
    const idx=Math.floor((phase*speed)/140)%AGENT_WALK_FRAMES;
    const walk=frames[idx];
    if(walk&&walk.complete&&walk.naturalWidth>0)sprite=walk;
  }
  if(sprite&&sprite.complete&&sprite.naturalWidth>0){
    ctx.save();
    ctx.translate(x,y-1);
    ctx.scale(facing,1);
    ctx.drawImage(sprite,-size/2,-size/2,size,size);
    ctx.restore();
  }else{
    ctx.fillStyle=ROLE_COLORS[a.role]||"#77f2ad";ctx.beginPath();ctx.arc(x,y,selected?5.5:3.5,0,Math.PI*2);ctx.fill();
  }
  if(a.runtime.lastProvider&&a.runtime.lastProvider!=="local"){
    ctx.strokeStyle=PROVIDER_RING[a.runtime.lastProvider]||"#d393ff";ctx.lineWidth=a.runtime.providerStatus==="pending"?1.8:.8;
    ctx.beginPath();ctx.arc(x,y,a.runtime.providerStatus==="pending"?11:9.5,0,Math.PI*2);ctx.stroke();
  }
  if(a.body.hp<45){ctx.strokeStyle="#ff7b7b";ctx.lineWidth=1.2;ctx.beginPath();ctx.arc(x,y,10,0,Math.PI*2);ctx.stroke()}
  if(a.inventory.amount>0){ctx.fillStyle=a.inventory.type==="water"?"#55b5ff":a.inventory.type==="food"?"#df73ff":"#b7804b";ctx.fillRect(x-2.5,y+size/2-1,5,2)}
  if(selected){
    ctx.strokeStyle="#fff";ctx.lineWidth=1;ctx.beginPath();ctx.arc(x,y,12,0,Math.PI*2);ctx.stroke();
    ctx.fillStyle="#fff";ctx.font="10px system-ui";ctx.fillText(a.name,x+14,y-8);
    if(a.mind.target){ctx.strokeStyle="#fff6";ctx.setLineDash([4,4]);ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(a.mind.target.x,a.mind.target.y);ctx.stroke();ctx.setLineDash([])}
  }
}
function focusedThought(agent){
  if(!agent)return "";
  const goal=String(agent.mind?.goal||"observe").replace(/[_-]+/g," ");
  const reason=String(agent.mind?.goalReason||"").trim();
  const plan=String(agent.mind?.plan||"").trim();
  const action=String(agent.runtime?.lastActionType||ACTION.WAIT).replace(/[_-]+/g," ");
  const detail=reason||plan;
  const text=`${goal} · ${action}${detail?` · ${detail}`:""}`.replace(/\s+/g," ").trim();
  return text.length>92?`${text.slice(0,89)}…`:text;
}
function drawFocusedThought(agent){
  if(!agent||!agent.alive)return "";
  const text=focusedThought(agent);if(!text)return "";
  const p=worldToScreen(visualAgentPosition(agent)),padding=7,font="12px system-ui";
  ctx.save();ctx.font=font;const maxWidth=Math.min(245,Math.max(120,CSS_W-24)),width=Math.min(maxWidth,ctx.measureText(`💭 ${text}`).width+padding*2),height=30;
  const x=clamp(p.x-width/2,8,CSS_W-width-8),y=clamp(p.y-48,8,CSS_H-height-8),radius=9;
  ctx.fillStyle="#06100cf2";ctx.strokeStyle="#77f2adbb";ctx.lineWidth=1;ctx.beginPath();ctx.roundRect(x,y,width,height,radius);ctx.fill();ctx.stroke();
  ctx.fillStyle="#eafff1";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillText(`💭 ${text}`,x+width/2,y+height/2,maxWidth-padding*2);ctx.restore();
  return text;
}
let renderDirty=true,lastRenderedTick=-1;
let lastHudAt=0,lastHudTick=-1,lastHudState=null;
let lastIntegrityAt=-Infinity,lastIntegrity={ok:true,errors:[]};
let lastEventStore=null,lastEventId=-1;
let lastInspectorState=null,lastInspectorTick=-1,lastInspectorAgentId=null;
function markRenderDirty(){renderDirty=true}
addEventListener("resize",markRenderDirty);
addEventListener("resize",()=>{camera.zoom=Math.max(camera.zoom,fitZoom());camera.center=clampCameraCenter(camera.center,camera.zoom)});

function render(force=false){
  const state=runtime.state;const selected=syncCameraToSelected();const v=worldView();
  // Render is independent from authoritative ticks: interpolation and effects advance every frame.
  // Do not gate this on state.tick or renderDirty; a two-second world interval still needs continuous animation.
  ctx.setTransform(DPR,0,0,DPR,0,0);ctx.fillStyle="#020806";ctx.fillRect(0,0,CSS_W,CSS_H);
  ctx.save();ctx.translate(v.ox,v.oy);ctx.scale(v.scale,v.scale);
  drawBackground(state);for(const r of state.resources)drawResource(r);drawCamp(state);drawMessageEffects(state);
  for(const a of state.agents)drawAgent(a,a===selected);
  ctx.restore();
  drawFocusedThought(selected);
  lastRenderedTick=state.tick;renderDirty=false;return true;
}

function formatEvent(event){return `T${event.tick} · ${event.message}`}
function updateEventLog(force=false){
  const events=runtime.events.recent(24).reverse();
  const latestId=events.at(-1)?.id??-1;
  if(!force&&lastEventStore===runtime.events&&lastEventId===latestId)return false;
  ui.eventLog.innerHTML=events.map(e=>`<div class="${e.severity}">${escapeHtml(formatEvent(e))}</div>`).join("")||"<div>ยังไม่มีเหตุการณ์</div>";
  lastEventStore=runtime.events;lastEventId=latestId;return true;
}
function escapeHtml(text){return String(text).replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[ch]))}
function setBar(el,value){el.style.width=`${clamp(value,0,100)}%`}
function updateInspector(force=false){
  const a=runtime.selectedAgentId?runtime.state.agentById.get(runtime.selectedAgentId):null;
  if(!force&&lastInspectorState===runtime.state&&lastInspectorTick===runtime.state.tick&&lastInspectorAgentId===runtime.selectedAgentId)return false;
  if(!a){ui.inspector.style.display="none";lastInspectorState=runtime.state;lastInspectorTick=runtime.state.tick;lastInspectorAgentId=runtime.selectedAgentId;return true}
  ui.inspector.style.display="block";
  ui.iname.textContent=`${a.name} · ${a.role.toUpperCase()}${a.alive?"":" · DEAD"}`;
  ui.imeta.textContent=`ID ${a.id} · session ${a.runtime.providerSessionId} · carry ${a.inventory.type||"-"} ${round1(a.inventory.amount)}/${a.capacity} · facts ${a.mind.facts.size} · failed ${a.mind.failedActions}`;
  setBar(ui.bhp,a.body.hp);setBar(ui.bhunger,100-a.body.hunger);setBar(ui.bthirst,100-a.body.thirst);setBar(ui.benergy,a.body.energy);
  ui.igoal.textContent=`goal: ${a.mind.goal}\nreason: ${a.mind.goalReason}\nplan: ${a.mind.plan}\nlast action: ${a.runtime.lastActionType}\nlast outcome: ${a.runtime.lastOutcome?a.runtime.lastOutcome.message:"-"}`;
  const validation=a.runtime.lastValidation;
  ui.iprovider.textContent=`mode: ${runtime.decisionRouter.label()}\nsessionId: ${a.runtime.providerSessionId}\nlast provider: ${a.runtime.lastProvider}\nstatus: ${a.runtime.providerStatus}\nvalidation: ${validation?(validation.ok?"PASS":"REJECT · "+validation.errors.join(" | ")):"-"}`;
  ui.irequest.textContent=clippedJson(a.runtime.lastDecisionRequest,4200);
  ui.iresponse.textContent=clippedJson(a.runtime.lastDecisionResponse,3200);
  const o=a.runtime.lastObservation,oc=a.runtime.lastObservationContract;
  ui.iobs.textContent=o?`protocol=${o.protocol}\nobservationId=${o.observationId}\ncontract=${oc&&oc.ok?"PASS":"FAIL"}\ntick=${o.tick}\nself=(${o.self.x},${o.self.y}) hp=${o.self.hp}\nvisibleResources=${o.visibleResources.length}\nnearbyAgents=${o.nearbyAgents.length}\nmessages=${o.messages.length}\ncampVisible=${o.camp.visible}\nstorm=${o.environment.stormActive}`:"(no observation yet)";
  const trustTop=[...a.social.trust.entries()].sort((x,y)=>y[1]-x[1]).slice(0,8).map(([id,v])=>`Astra-${String(id).padStart(3,"0")}: trust=${v.toFixed(2)}`).join("\n");
  const rep=a.social.reputation;ui.isocial.textContent=`credibility=${rep.credibility.toFixed(2)} · sent=${rep.messagesSent} · reports=${rep.reports} · offers=${rep.offers} · warnings=${rep.warnings}\nclaims verified=${rep.claimsVerified} · accurate=${rep.accurateClaims} · misleading=${rep.misleadingClaims}\n${trustTop||"no peer trust evidence yet"}`;
  ui.iwm.textContent=[...a.mind.facts.values()].sort((x,y)=>y.lastSeenTick-x.lastSeenTick).slice(0,13)
    .map(f=>`${f.key} = ${JSON.stringify(f.value)} [c=${f.confidence.toFixed(2)} src=${f.source}]`).join("\n")||"(empty symbolic model)";
  ui.imem.textContent=a.mind.memory.slice(-10).reverse().map(m=>`T${m.tick} ${m.kind}: ${m.text}`).join("\n")||"(empty memory)";
  ui.itrace.innerHTML=a.runtime.trace.slice(-8).reverse().map(t=>`<div>T${t.tick} ${escapeHtml(t.phase)} · ${escapeHtml(t.text)}</div>`).join("");
  lastInspectorState=runtime.state;lastInspectorTick=runtime.state.tick;lastInspectorAgentId=runtime.selectedAgentId;return true;
}
function updatePipeline(){
  document.querySelectorAll(".stage").forEach((el,i)=>{el.classList.toggle("done",i<=runtime.phaseIndex);el.classList.toggle("active",i===runtime.phaseIndex)});
  ui.runtimeMeta.textContent=`seed ${runtime.seed} · ${runtime.phase} · ${runtime.decisionRouter.label()} · ${PROTOCOL.action}`;
}
function updateHud(force=false){
  const s=runtime.state,now=performance.now();
  if(!force&&lastHudState===s&&lastHudTick===s.tick&&now-lastHudAt<180)return false;
  lastHudAt=now;lastHudTick=s.tick;lastHudState=s;
  const alive=s.agents.filter(a=>a.alive).length;
  if(force||now-lastIntegrityAt>=1000){lastIntegrity=runtime.selfTest();lastIntegrityAt=now}
  const test=lastIntegrity;
  ui.alive.textContent=alive;ui.day.textContent=s.day;ui.tick.textContent=s.tick;ui.food.textContent=Math.floor(s.stock.food);ui.water.textContent=Math.floor(s.stock.water);
  ui.wood.textContent=Math.floor(s.stock.wood);ui.shelter.textContent=s.camp.shelter;ui.knowledge.textContent=runtime.unionFactCount();ui.coop.textContent=`${Math.round(runtime.cooperationRate())}%`;
  const pm=runtime.decisionRouter.metrics;
  ui.queued.textContent=s.metrics.lastActionCount;ui.failures.textContent=s.metrics.failedActions;ui.providerCalls.textContent=pm.calls;ui.invalidDecisions.textContent=pm.invalid;ui.fallbacks.textContent=pm.fallbacks;ui.pending.textContent=runtime.decisionRouter.pendingCount();ui.obsErrors.textContent=s.metrics.observationContractErrors;
  ui.messagesSent.textContent=s.metrics.socialMessages;ui.verifiedClaims.textContent=runtime.verifiedClaims();ui.avgCredibility.textContent=`${Math.round(runtime.averageCredibility()*100)}%`;
  ui.integrity.textContent=test.ok?"PASS":"FAIL";ui.integrity.className=test.ok?"ok":"bad";
  ui.providerBadge.className=`provider-badge${runtime.decisionRouter.pendingCount()?" pending":pm.providerErrors||pm.invalid?" error":""}`;
  ui.providerBadge.querySelector("span").textContent=`${runtime.decisionRouter.label()} · v1 · ${runtime.decisionRouter.pendingCount()} pending`;
  updatePipeline();updateEventLog(force);updateInspector(force);return true;
}
function pickAgent(clientX,clientY){
  const p=screenToWorld(clientX,clientY);let best=null,bestD=18;
  for(const a of runtime.state.agents){const ap=visualAgentPosition(a),d=Math.hypot(ap.x-p.x,ap.y-p.y);if(d<bestD){bestD=d;best=a}}
  if(best){focusCamera(best.id);renderDirty=true;updateInspector(true);render(true)}
}
const activePointers=new Map();let pointerStart=null,pointerMoved=false,pinchDistance=0;
function pointerDistance(){const points=[...activePointers.values()];return points.length<2?0:Math.hypot(points[0].x-points[1].x,points[0].y-points[1].y)}
function pointerMidpoint(){const points=[...activePointers.values()];return points.length<2?{x:CSS_W/2,y:CSS_H/2}:{x:(points[0].x+points[1].x)/2,y:(points[0].y+points[1].y)/2}}
canvas.addEventListener("pointerdown",e=>{
  const p=screenPoint(e.clientX,e.clientY);activePointers.set(e.pointerId,p);canvas.setPointerCapture?.(e.pointerId);
  if(activePointers.size===1){pointerStart=p;pointerMoved=false}else{pinchDistance=pointerDistance();pointerMoved=true}
});
canvas.addEventListener("pointermove",e=>{
  if(!activePointers.has(e.pointerId))return;const previous=activePointers.get(e.pointerId),next=screenPoint(e.clientX,e.clientY);activePointers.set(e.pointerId,next);
  if(activePointers.size>=2){const distanceNow=pointerDistance(),mid=pointerMidpoint();if(pinchDistance>0&&distanceNow>0)zoomCameraAt(camera.zoom*distanceNow/pinchDistance,mid.x,mid.y);pinchDistance=distanceNow;pointerMoved=true;render(true);return}
  if(pointerStart){const dx=next.x-previous.x,dy=next.y-previous.y;if(Math.hypot(next.x-pointerStart.x,next.y-pointerStart.y)>7)pointerMoved=true;if(pointerMoved){camera.followSelected=false;camera.center=clampCameraCenter({x:camera.center.x-dx/camera.zoom,y:camera.center.y-dy/camera.zoom});render(true)}}
});
function finishPointer(e){const p=activePointers.get(e.pointerId);activePointers.delete(e.pointerId);if(activePointers.size){pointerStart=[...activePointers.values()][0];pointerMoved=true;pinchDistance=pointerDistance();return}if(p&&!pointerMoved)pickAgent(e.clientX,e.clientY);pointerStart=null;pointerMoved=false;pinchDistance=0}
canvas.addEventListener("pointerup",finishPointer);canvas.addEventListener("pointercancel",()=>{activePointers.clear();pointerStart=null;pointerMoved=false;pinchDistance=0});
canvas.addEventListener("wheel",e=>{e.preventDefault();const p=screenPoint(e.clientX,e.clientY);zoomCameraBy(e.deltaY>0?.88:1.14,p.x,p.y);render(true)},{passive:false});

$("zoomInBtn").onclick=()=>{zoomCameraBy(1.25);render(true)};
$("zoomOutBtn").onclick=()=>{zoomCameraBy(.8);render(true)};
$("fitMapBtn").onclick=()=>{fitCameraToMap();render(true)};
$("focusBtn").onclick=()=>{focusCamera();render(true)};

window.AstraLifeCamera=Object.freeze({
  config:CAMERA_CONFIG,
  getState:()=>({center:{...camera.center},zoom:camera.zoom,fitZoom:fitZoom(),followSelected:camera.followSelected,selectedAgentId:runtime.selectedAgentId,focusedAgentId:livingAgent()?.id||null}),
  worldView:()=>({...worldView(),center:{...camera.center}}),
  worldToScreen:point=>({...worldToScreen(point)}),
  screenToWorld:(x,y)=>({...screenLocalToWorld(x,y)}),
  focusAgent:id=>{const target=focusCamera(id);render(true);return target?{id:target.id,state:{...camera.center}}:null},
  reset:()=>{const target=resetCameraToDefault();render(true);return target?target.id:null},
  fitToMap:()=>{const view=fitCameraToMap();render(true);return {...view}},
  zoomBy:(factor,x,y)=>{const view=zoomCameraBy(factor,x,y);render(true);return {...view}},
  getFocusedThought:()=>{const target=livingAgent();return {agentId:target?.id||null,text:focusedThought(target)}},
  pickAt:(x,y)=>{const before=runtime.selectedAgentId;pickAgent(x+canvas.getBoundingClientRect().left,y+canvas.getBoundingClientRect().top);return {before,after:runtime.selectedAgentId}}
});

ensureCameraTarget();

$("toggle").onclick=e=>{runtime.state.running=!runtime.state.running;e.currentTarget.textContent=runtime.state.running?"⏸ หยุด":"▶ เดินต่อ"};
$("stepBtn").onclick=()=>{AstraColony.step();render(true);updateHud(true)};
$("addBtn").onclick=()=>{runtime.spawnAgents(20);renderDirty=true;render(true);updateHud(true)};
$("stormBtn").onclick=()=>{runtime.triggerStorm();renderDirty=true;render(true);updateHud(true)};
$("rumorBtn").onclick=()=>{const out=runtime.injectRumor();if(!out.ok&&out.error)runtime.events.emit(runtime.state.tick,"RUMOR",out.error,{},"danger");renderDirty=true;render(true);updateHud(true)};
$("resetBtn").onclick=()=>{runtime.reset($("seedInput").value.trim()||"ASTRA-2026");resetVisualInterpolation();resetCameraToDefault();$("toggle").textContent="⏸ หยุด";render(true);updateHud(true)};
$("applySeedBtn").onclick=()=>{$("resetBtn").click()};
$("speedSelect").onchange=e=>runtime.state.speed=clamp(Number(e.target.value)||1,1,8);
$("providerSelect").onchange=e=>{runtime.setProviderMode(e.target.value);$("endpointInput").disabled=e.target.value!==PROVIDER_MODE.REMOTE;updateHud()};
$("endpointInput").disabled=true;$("endpointInput").onchange=e=>runtime.setProviderEndpoint(e.target.value);
$("endpointInput").oninput=e=>runtime.setProviderEndpoint(e.target.value);
$("exportBtn").onclick=()=>{
  const blob=new Blob([JSON.stringify(runtime.snapshot(),null,2)],{type:"application/json"});const url=URL.createObjectURL(blob);const a=document.createElement("a");
  a.href=url;a.download=`astra-colony-v0.4-${runtime.seed}-tick-${runtime.state.tick}.json`;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),800);
};

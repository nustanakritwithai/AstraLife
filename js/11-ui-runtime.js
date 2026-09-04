function worldView(){
  const scale=Math.min(CSS_W/SPACE.width,CSS_H/SPACE.height);
  const width=SPACE.width*scale,height=SPACE.height*scale;
  return {scale,ox:(CSS_W-width)/2,oy:(CSS_H-height)/2};
}
function screenToWorld(clientX,clientY){
  const r=canvas.getBoundingClientRect(),v=worldView();
  return {x:(clientX-r.left-v.ox)/v.scale,y:(clientY-r.top-v.oy)/v.scale};
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
    ctx.beginPath();ctx.moveTo(a.body.x,a.body.y);ctx.lineTo(b.body.x,b.body.y);ctx.stroke();
  }
}
function drawAgent(a,selected){
  if(!a.alive){ctx.fillStyle="#3c4741";ctx.fillRect(a.body.x-2,a.body.y-2,4,4);return}
  ctx.fillStyle=ROLE_COLORS[a.role]||"#77f2ad";ctx.beginPath();ctx.arc(a.body.x,a.body.y,selected?5.5:3.5,0,Math.PI*2);ctx.fill();
  if(a.runtime.lastProvider&&a.runtime.lastProvider!=="local"){
    ctx.strokeStyle=PROVIDER_RING[a.runtime.lastProvider]||"#d393ff";ctx.lineWidth=a.runtime.providerStatus==="pending"?1.8:.8;
    ctx.beginPath();ctx.arc(a.body.x,a.body.y,a.runtime.providerStatus==="pending"?8:6.5,0,Math.PI*2);ctx.stroke();
  }
  if(a.body.hp<45){ctx.strokeStyle="#ff7b7b";ctx.lineWidth=1.2;ctx.beginPath();ctx.arc(a.body.x,a.body.y,7,0,Math.PI*2);ctx.stroke()}
  if(a.inventory.amount>0){ctx.fillStyle=a.inventory.type==="water"?"#55b5ff":a.inventory.type==="food"?"#df73ff":"#b7804b";ctx.fillRect(a.body.x-2.5,a.body.y+5,5,2)}
  if(selected){
    ctx.strokeStyle="#fff";ctx.lineWidth=1;ctx.beginPath();ctx.arc(a.body.x,a.body.y,10,0,Math.PI*2);ctx.stroke();
    ctx.fillStyle="#fff";ctx.font="10px system-ui";ctx.fillText(a.name,a.body.x+12,a.body.y-6);
    if(a.mind.target){ctx.strokeStyle="#fff6";ctx.setLineDash([4,4]);ctx.beginPath();ctx.moveTo(a.body.x,a.body.y);ctx.lineTo(a.mind.target.x,a.mind.target.y);ctx.stroke();ctx.setLineDash([])}
  }
}
function render(){
  const state=runtime.state;const v=worldView();
  ctx.setTransform(DPR,0,0,DPR,0,0);ctx.fillStyle="#020806";ctx.fillRect(0,0,CSS_W,CSS_H);
  ctx.save();ctx.translate(v.ox,v.oy);ctx.scale(v.scale,v.scale);
  drawBackground(state);for(const r of state.resources)drawResource(r);drawCamp(state);drawMessageEffects(state);
  const selected=runtime.selectedAgentId?state.agentById.get(runtime.selectedAgentId):null;
  for(const a of state.agents)drawAgent(a,a===selected);
  ctx.restore();
}

function formatEvent(event){return `T${event.tick} · ${event.message}`}
function updateEventLog(){
  const events=runtime.events.recent(24).reverse();
  ui.eventLog.innerHTML=events.map(e=>`<div class="${e.severity}">${escapeHtml(formatEvent(e))}</div>`).join("")||"<div>ยังไม่มีเหตุการณ์</div>";
}
function escapeHtml(text){return String(text).replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[ch]))}
function setBar(el,value){el.style.width=`${clamp(value,0,100)}%`}
function updateInspector(){
  const a=runtime.selectedAgentId?runtime.state.agentById.get(runtime.selectedAgentId):null;
  if(!a){ui.inspector.style.display="none";return}
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
}
function updatePipeline(){
  document.querySelectorAll(".stage").forEach((el,i)=>{el.classList.toggle("done",i<=runtime.phaseIndex);el.classList.toggle("active",i===runtime.phaseIndex)});
  ui.runtimeMeta.textContent=`seed ${runtime.seed} · ${runtime.phase} · ${runtime.decisionRouter.label()} · ${PROTOCOL.action}`;
}
function updateHud(){
  const s=runtime.state;const alive=s.agents.filter(a=>a.alive).length;const test=runtime.selfTest();
  ui.alive.textContent=alive;ui.day.textContent=s.day;ui.tick.textContent=s.tick;ui.food.textContent=Math.floor(s.stock.food);ui.water.textContent=Math.floor(s.stock.water);
  ui.wood.textContent=Math.floor(s.stock.wood);ui.shelter.textContent=s.camp.shelter;ui.knowledge.textContent=runtime.unionFactCount();ui.coop.textContent=`${Math.round(runtime.cooperationRate())}%`;
  const pm=runtime.decisionRouter.metrics;
  ui.queued.textContent=s.metrics.lastActionCount;ui.failures.textContent=s.metrics.failedActions;ui.providerCalls.textContent=pm.calls;ui.invalidDecisions.textContent=pm.invalid;ui.fallbacks.textContent=pm.fallbacks;ui.pending.textContent=runtime.decisionRouter.pendingCount();ui.obsErrors.textContent=s.metrics.observationContractErrors;
  ui.messagesSent.textContent=s.metrics.socialMessages;ui.verifiedClaims.textContent=runtime.verifiedClaims();ui.avgCredibility.textContent=`${Math.round(runtime.averageCredibility()*100)}%`;
  ui.integrity.textContent=test.ok?"PASS":"FAIL";ui.integrity.className=test.ok?"ok":"bad";
  ui.providerBadge.className=`provider-badge${runtime.decisionRouter.pendingCount()?" pending":pm.providerErrors||pm.invalid?" error":""}`;
  ui.providerBadge.querySelector("span").textContent=`${runtime.decisionRouter.label()} · v1 · ${runtime.decisionRouter.pendingCount()} pending`;
  updatePipeline();updateEventLog();updateInspector();
}
function pickAgent(clientX,clientY){
  const p=screenToWorld(clientX,clientY);let best=null,bestD=18;
  for(const a of runtime.state.agents){const d=Math.hypot(a.body.x-p.x,a.body.y-p.y);if(d<bestD){bestD=d;best=a}}
  if(best){runtime.selectedAgentId=best.id;updateInspector()}
}
canvas.addEventListener("click",e=>pickAgent(e.clientX,e.clientY));
canvas.addEventListener("touchstart",e=>{const t=e.touches[0];if(t)pickAgent(t.clientX,t.clientY)},{passive:true});

$("toggle").onclick=e=>{runtime.state.running=!runtime.state.running;e.currentTarget.textContent=runtime.state.running?"⏸ หยุด":"▶ เดินต่อ"};
$("stepBtn").onclick=()=>{runtime.tickOnce();render();updateHud()};
$("addBtn").onclick=()=>{runtime.spawnAgents(20);updateHud()};
$("stormBtn").onclick=()=>{runtime.triggerStorm();updateHud()};
$("rumorBtn").onclick=()=>{const out=runtime.injectRumor();if(!out.ok&&out.error)runtime.events.emit(runtime.state.tick,"RUMOR",out.error,{},"danger");updateHud()};
$("resetBtn").onclick=()=>{runtime.reset($("seedInput").value.trim()||"ASTRA-2026");$("toggle").textContent="⏸ หยุด";render();updateHud()};
$("applySeedBtn").onclick=()=>{$("resetBtn").click()};
$("speedSelect").onchange=e=>runtime.state.speed=clamp(Number(e.target.value)||1,1,8);
$("providerSelect").onchange=e=>{runtime.setProviderMode(e.target.value);$("endpointInput").disabled=e.target.value!==PROVIDER_MODE.REMOTE;updateHud()};
$("endpointInput").disabled=true;$("endpointInput").onchange=e=>runtime.setProviderEndpoint(e.target.value);
$("endpointInput").oninput=e=>runtime.setProviderEndpoint(e.target.value);
$("exportBtn").onclick=()=>{
  const blob=new Blob([JSON.stringify(runtime.snapshot(),null,2)],{type:"application/json"});const url=URL.createObjectURL(blob);const a=document.createElement("a");
  a.href=url;a.download=`astra-colony-v0.4-${runtime.seed}-tick-${runtime.state.tick}.json`;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),800);
};

function contractViewValue(){
  const bundle=runtime.contractBundle(),view=$("contractView").value;
  if(view==="observation")return bundle.observationSchema;
  if(view==="request")return bundle.decisionRequestSchema;
  if(view==="response")return bundle.decisionResponseSchema;
  if(view==="action")return bundle.actionSchema;
  if(view==="communication")return bundle.communicationSchema;
  if(view==="latest"){
    const a=runtime.selectedAgentId?runtime.state.agentById.get(runtime.selectedAgentId):runtime.state.agents.find(a=>a.alive);
    return a&&a.runtime.lastDecisionRequest?a.runtime.lastDecisionRequest:{message:"Run at least one tick, then select an Agent."};
  }
  if(view==="server")return NODE_BRIDGE_EXAMPLE;
  return bundle;
}
function updateContractModal(){
  const value=contractViewValue();ui.contractContent.textContent=typeof value==="string"?value:JSON.stringify(value,null,2);
  ui.contractStatus.textContent=$("contractView").value==="server"?"ตัวอย่างนี้เป็น bridge skeleton ไม่ได้เรียก Astra จริง — แทนฟังก์ชัน decide() ด้วย provider ฝั่ง server ของคุณ":"Strict JSON + Social contract · ASK / REPORT / REQUEST_HELP / OFFER / WARN · verified claims update Trust";
}
$("contractBtn").onclick=()=>{ui.contractModal.classList.add("open");updateContractModal()};
$("contractClose").onclick=()=>ui.contractModal.classList.remove("open");
ui.contractModal.addEventListener("click",e=>{if(e.target===ui.contractModal)ui.contractModal.classList.remove("open")});
$("contractView").onchange=updateContractModal;
$("copyContractBtn").onclick=async()=>{
  const text=ui.contractContent.textContent;try{await navigator.clipboard.writeText(text);ui.contractStatus.textContent="คัดลอกแล้ว"}catch{ui.contractStatus.textContent="เบราว์เซอร์ไม่อนุญาต clipboard — เลือกข้อความในช่องแทน"}
};
$("downloadContractBtn").onclick=()=>{
  const view=$("contractView").value,text=ui.contractContent.textContent,type=view==="server"?"text/javascript":"application/json";
  const blob=new Blob([text],{type}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=view==="server"?"astra_provider_bridge_example.mjs":`astra-colony-${view}-contract-v1.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),800);
};

function refreshProviderOptions(){
  const select=$("providerSelect"),existing=new Set([...select.options].map(o=>o.value));
  for(const p of runtime.registry.list())if(p.kind==="custom"&&!existing.has(`provider:${p.id}`)){
    const option=document.createElement("option");option.value=`provider:${p.id}`;option.textContent=`Custom · ${p.label}`;select.appendChild(option);
  }
}

const FRAME_PACING=Object.freeze({intervalMs:2000,simulationTicksPerSecond:.5,maxElapsedMs:100,maxTicksPerFrame:2,maxBacklogTicks:6});
let simulationLast=0,tickBudget=0,lastUi=0;
const frameStats={frames:0,totalTicks:0,maxTicksPerFrame:0,maxBacklogTicks:0,droppedTicks:0,lastElapsedMs:0};
let visualPrevious=null,visualNext=null,visualElapsedMs=0;

function captureVisualSnapshot(state){
  const agents=new Map();
  for(const agent of state.agents)agents.set(agent.id,{x:agent.body.x,y:agent.body.y,alive:agent.alive});
  return {tick:state.tick,agents};
}
function resetVisualInterpolation(){
  const snapshot=captureVisualSnapshot(runtime.state);
  visualPrevious=snapshot;visualNext=snapshot;visualElapsedMs=0;
}
function rememberAuthoritativeTick(previous,next){
  visualPrevious=previous;visualNext=next;visualElapsedMs=0;
}
function visualAlpha(){
  return clamp(visualElapsedMs/FRAME_PACING.intervalMs,0,1);
}
function visualAgentPosition(agent){
  const current={x:agent.body.x,y:agent.body.y};
  const from=visualPrevious&&visualPrevious.agents.get(agent.id)||current;
  const to=visualNext&&visualNext.agents.get(agent.id)||current;
  const alpha=visualAlpha();
  return {x:from.x+(to.x-from.x)*alpha,y:from.y+(to.y-from.y)*alpha};
}
function visualDiagnostics(){
  return {alpha:visualAlpha(),intervalMs:FRAME_PACING.intervalMs,previousTick:visualPrevious?visualPrevious.tick:null,nextTick:visualNext?visualNext.tick:null,visualElapsedMs,stateTick:runtime.state.tick};
}
function resetFramePacing(){
  simulationLast=0;tickBudget=0;lastUi=0;
  for(const key of Object.keys(frameStats))frameStats[key]=0;
}
function advanceSimulation(elapsedMs,{ignoreRunning=false}={}){
  const elapsed=Math.min(FRAME_PACING.maxElapsedMs,Math.max(0,Number(elapsedMs)||0));
  frameStats.lastElapsedMs=elapsed;
  if(!runtime.state.running&&!ignoreRunning){tickBudget=0;return 0}
  const scaledElapsed=elapsed*runtime.state.speed;
  const requested=tickBudget+scaledElapsed/FRAME_PACING.intervalMs;
  visualElapsedMs+=scaledElapsed;
  if(requested>FRAME_PACING.maxBacklogTicks)frameStats.droppedTicks+=requested-FRAME_PACING.maxBacklogTicks;
  tickBudget=Math.min(FRAME_PACING.maxBacklogTicks,requested);
  const ticks=Math.min(Math.floor(tickBudget+1e-9),FRAME_PACING.maxTicksPerFrame);
  for(let i=0;i<ticks;i++){
    const previous=captureVisualSnapshot(runtime.state);
    runtime.tickOnce();
    const next=captureVisualSnapshot(runtime.state);
    rememberAuthoritativeTick(previous,next);
    visualElapsedMs=Math.max(0,visualElapsedMs-FRAME_PACING.intervalMs);
  }
  if(ticks===0)visualElapsedMs=Math.min(visualElapsedMs,FRAME_PACING.intervalMs);
  tickBudget-=ticks;
  frameStats.frames++;frameStats.totalTicks+=ticks;
  frameStats.maxTicksPerFrame=Math.max(frameStats.maxTicksPerFrame,ticks);
  frameStats.maxBacklogTicks=Math.max(frameStats.maxBacklogTicks,tickBudget);
  return ticks;
}
function simulationFrame(ts){
  const elapsed=simulationLast?Math.max(0,ts-simulationLast):0;simulationLast=ts;
  advanceSimulation(elapsed);requestAnimationFrame(simulationFrame);
}
function renderFrame(ts){
  render();if(ts-lastUi>180){updateHud();lastUi=ts}requestAnimationFrame(renderFrame);
}

window.AstraLifeFramePacing=Object.freeze({
  config:FRAME_PACING,
  getStats:()=>({...frameStats,backlogTicks:tickBudget}),
  getVisualState:()=>visualDiagnostics(),
  getInterpolatedAgentPosition:agentId=>{const agent=runtime.state.agentById.get(Number(agentId));return agent?visualAgentPosition(agent):null},
  reset:()=>{resetFramePacing();resetVisualInterpolation();return {...frameStats,backlogTicks:tickBudget}},
  // Diagnostic hook used by the browser acceptance test. It calls the exact same
  // bounded scheduler without depending on wall-clock requestAnimationFrame timing.
  advanceForTest:elapsedMs=>{const ticks=advanceSimulation(elapsedMs,{ignoreRunning:true});return {ticks,...frameStats,backlogTicks:tickBudget,visual:visualDiagnostics()}}
});

window.AstraColony=Object.freeze({
  version:VERSION,protocols:PROTOCOL,
  step:()=>{const previous=captureVisualSnapshot(runtime.state);const out=runtime.tickOnce();rememberAuthoritativeTick(previous,captureVisualSnapshot(runtime.state));return out},
  runTicks:n=>{const previous=captureVisualSnapshot(runtime.state);const out=runtime.runTicks(n);rememberAuthoritativeTick(previous,captureVisualSnapshot(runtime.state));return out},
  reset:seed=>{runtime.reset(seed);resetVisualInterpolation();render(true);updateHud(true);return runtime.snapshot()},
  snapshot:()=>runtime.snapshot(),
  selfTest:()=>runtime.selfTest(),
  contractBundle:()=>runtime.contractBundle(),
  listProviders:()=>runtime.registry.list(),
  registerProvider:(id,adapter,meta={})=>{const entry=runtime.registry.register(id,adapter,{...meta,kind:"custom"});refreshProviderOptions();return {id:entry.id,...entry.meta}},
  setProviderMode:mode=>{runtime.setProviderMode(mode);$("providerSelect").value=mode;updateHud();return mode},
  setProviderEndpoint:endpoint=>{$("endpointInput").value=endpoint;return runtime.setProviderEndpoint(endpoint)},
  injectRumor:agentId=>runtime.injectRumor(agentId),
  getLatestRequest:agentId=>{const a=runtime.state.agentById.get(Number(agentId));return a?a.runtime.lastDecisionRequest:null},
  getLatestObservation:agentId=>{const a=runtime.state.agentById.get(Number(agentId));return a?a.runtime.lastObservation:null},
  validateDecision:(agentId,response)=>{const a=runtime.state.agentById.get(Number(agentId));if(!a||!a.runtime.lastDecisionRequest)return {ok:false,errors:["agent or latest request unavailable"]};return runtime.validator.validate(response,a.runtime.lastDecisionRequest,runtime.state)},
  get runtime(){return runtime}
});

resetFramePacing();resetVisualInterpolation();updateHud(true);requestAnimationFrame(simulationFrame);requestAnimationFrame(renderFrame);

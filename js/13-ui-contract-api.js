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

const SIMULATION_TICKS_PER_SECOND=6;
const SIMULATION_INTERVAL_MS=1000/SIMULATION_TICKS_PER_SECOND;
const FRAME_PACING=Object.freeze({intervalMs:SIMULATION_INTERVAL_MS,maxElapsedMs:100,maxTicksPerFrame:2,maxBacklogTicks:6});
let last=0,tickBudget=0,lastUi=0;
const frameStats={frames:0,totalTicks:0,maxTicksPerFrame:0,maxBacklogTicks:0,droppedTicks:0,lastElapsedMs:0};
function resetFramePacing(){last=0;tickBudget=0;lastUi=0;for(const key of Object.keys(frameStats))frameStats[key]=0}
function advanceSimulation(elapsedMs,{ignoreRunning=false}={}){
  const elapsed=Math.min(FRAME_PACING.maxElapsedMs,Math.max(0,Number(elapsedMs)||0));
  frameStats.lastElapsedMs=elapsed;
  if(!runtime.state.running&&!ignoreRunning){tickBudget=0;return 0}
  const requested=tickBudget+elapsed/FRAME_PACING.intervalMs*runtime.state.speed;
  // A capped backlog prevents a background-tab pause or a slow mobile frame from
  // turning into a large catch-up burst. Excess wall-clock work is deliberately
  // dropped; the next frame starts from a bounded, playable schedule.
  if(requested>FRAME_PACING.maxBacklogTicks)frameStats.droppedTicks+=requested-FRAME_PACING.maxBacklogTicks;
  tickBudget=Math.min(FRAME_PACING.maxBacklogTicks,requested);
  const ticks=Math.min(Math.floor(tickBudget+1e-9),FRAME_PACING.maxTicksPerFrame);
  for(let i=0;i<ticks;i++)runtime.tickOnce();
  tickBudget-=ticks;
  frameStats.frames++;frameStats.totalTicks+=ticks;
  frameStats.maxTicksPerFrame=Math.max(frameStats.maxTicksPerFrame,ticks);
  frameStats.maxBacklogTicks=Math.max(frameStats.maxBacklogTicks,tickBudget);
  return ticks;
}
function frame(ts){
  const elapsed=last?Math.max(0,ts-last):0;last=ts;
  advanceSimulation(elapsed);
  render();if(ts-lastUi>180){updateHud();lastUi=ts}requestAnimationFrame(frame);
}

window.AstraLifeFramePacing=Object.freeze({
  config:FRAME_PACING,
  getStats:()=>({...frameStats,backlogTicks:tickBudget}),
  reset:()=>{resetFramePacing();return {...frameStats,backlogTicks:tickBudget}},
  // Diagnostic hook used by the browser acceptance test. It calls the exact same
  // bounded scheduler without depending on wall-clock requestAnimationFrame timing.
  advanceForTest:elapsedMs=>{const ticks=advanceSimulation(elapsedMs,{ignoreRunning:true});return {ticks,...frameStats,backlogTicks:tickBudget}}
});

window.AstraColony=Object.freeze({
  version:VERSION,protocols:PROTOCOL,
  step:()=>runtime.tickOnce(),
  runTicks:n=>runtime.runTicks(n),
  reset:seed=>{runtime.reset(seed);render(true);updateHud(true);return runtime.snapshot()},
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

updateHud(true);requestAnimationFrame(frame);

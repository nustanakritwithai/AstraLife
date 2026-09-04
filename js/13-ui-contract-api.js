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

let last=0,acc=0,lastUi=0;
function frame(ts){
  const elapsed=Math.min(100,ts-last||16);last=ts;
  if(runtime.state.running){
    acc+=elapsed;const interval=42;
    while(acc>=interval){for(let i=0;i<runtime.state.speed;i++)runtime.tickOnce();acc-=interval}
  }
  render();if(ts-lastUi>180){updateHud();lastUi=ts}requestAnimationFrame(frame);
}

window.AstraColony=Object.freeze({
  version:VERSION,protocols:PROTOCOL,
  step:()=>runtime.tickOnce(),
  runTicks:n=>runtime.runTicks(n),
  reset:seed=>{runtime.reset(seed);updateHud();return runtime.snapshot()},
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

updateHud();requestAnimationFrame(frame);

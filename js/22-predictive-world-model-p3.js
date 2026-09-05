(() => {
  "use strict";
  const VERSION="p3.0";
  const MAX_PREDICTIONS=96;
  function ensure(a){
    if(!a.mind.worldModel)a.mind.worldModel={version:VERSION,travel:{loadPenalty:.40,samples:0,mae:0},construction:{samples:0,mae:0},storm:{samples:0,mae:0},predictions:[]};
    if(!Array.isArray(a.mind.worldModel.predictions))a.mind.worldModel.predictions=[];
    return a.mind.worldModel;
  }
  function push(a,p){const wm=ensure(a);wm.predictions.push(Object.freeze({...p}));if(wm.predictions.length>MAX_PREDICTIONS)wm.predictions.splice(0,wm.predictions.length-MAX_PREDICTIONS);return p}
  const bucket=x=>x<.15?"empty":x<.55?"light":"heavy";
  function predictTravel(state,a,action){
    const wm=ensure(a),target={x:Number(action.payload?.x)||a.body.x,y:Number(action.payload?.y)||a.body.y};
    const d=Math.hypot(target.x-a.body.x,target.y-a.body.y)||0;
    const fatigue=clamp(a.body.energy/38,.42,1),weather=state.stormTicks>0?.63:1,speed=clamp(Number(action.payload?.speed)||1,.35,1.35);
    const baseStep=Math.min(d,3*fatigue*weather*speed);
    const loadRatio=clamp((a.inventory?.amount||0)/Math.max(1,a.capacity||1),0,1);
    const predictedEnergy=.014*baseStep*(1+loadRatio*wm.travel.loadPenalty);
    return push(a,{predictionId:`pred:${state.tick}:${a.id}:${action.id}`,model:"travel",actionId:action.id,createdTick:state.tick,horizonTick:state.tick,context:{loadRatio,loadBucket:bucket(loadRatio),stormActive:state.stormTicks>0,energy:a.body.energy,distance:d},predicted:{distance:baseStep,energyCost:predictedEnergy},status:"PENDING"});
  }
  function settleTravel(state,a,p,metrics,outcome){
    const wm=ensure(a),actualDistance=metrics.actualDistance,actualEnergy=metrics.actualEnergy;
    const error=Math.abs((p.predicted.energyCost||0)-actualEnergy);
    const old=wm.travel.loadPenalty,lr=.35,load=p.context.loadRatio;
    if(load>.001){const target=Math.max(0,actualEnergy/Math.max(.0001,.014*Math.max(actualDistance,.0001))-1)/load;wm.travel.loadPenalty=clamp(old+(target-old)*lr,0,1.5)}
    wm.travel.samples++;wm.travel.mae=((wm.travel.mae*(wm.travel.samples-1))+error)/wm.travel.samples;
    const settled=Object.freeze({...p,status:"RESOLVED",resolvedTick:state.tick,actual:{distance:actualDistance,energyCost:actualEnergy,ok:!!outcome.ok},error:{energyAbs:error,distanceAbs:Math.abs((p.predicted.distance||0)-actualDistance)},adjustment:{parameter:"travel.loadPenalty",before:old,after:wm.travel.loadPenalty}});
    const idx=wm.predictions.findIndex(x=>x.predictionId===p.predictionId);if(idx>=0)wm.predictions[idx]=settled;
    runtime.memory.remember(a,`travel prediction error ${round1(error)}; loadPenalty ${old.toFixed(3)}→${wm.travel.loadPenalty.toFixed(3)}`,"learning",{lesson:"adjust travel estimate for similar load",context:{kind:"prediction-outcome",model:"travel",predictionId:p.predictionId,loadBucket:p.context.loadBucket,error},importance:.82});
    return settled;
  }
  const oldResolveMove=ActionResolver.prototype.resolveMove;
  ActionResolver.prototype.resolveMove=function(state,a,action){
    const before={x:a.body.x,y:a.body.y,energy:a.body.energy},p=predictTravel(state,a,action);
    const outcome=oldResolveMove.call(this,state,a,action);
    const metrics={predictionId:p.predictionId,actualDistance:Math.hypot(a.body.x-before.x,a.body.y-before.y),actualEnergy:Math.max(0,before.energy-a.body.energy)};
    return Object.freeze({...outcome,p3Prediction:metrics});
  };
  const oldLearn=MemorySystem.prototype.learn;
  MemorySystem.prototype.learn=function(a,outcome){
    const result=oldLearn.call(this,a,outcome);
    const meta=outcome?.p3Prediction;if(meta){const wm=ensure(a),p=wm.predictions.find(x=>x.predictionId===meta.predictionId);if(p&&p.status==="PENDING")settleTravel(runtime.state,a,p,meta,outcome)}
    return result;
  };
  function predictConstruction(state,a,crewSize=2){const wm=ensure(a);return {model:"construction",predictedProgress:Math.max(0,crewSize*1.25),confidence:clamp(.45+wm.construction.samples*.02,.45,.8)}}
  function predictStormRisk(state,a){const wm=ensure(a);const thirst=clamp(a.body.thirst/100,0,1),hunger=clamp(a.body.hunger/100,0,1),shelterKnown=Number(a.mind.knownShelters||0);return {model:"storm",risk:clamp((state.stormTicks>0?.35:.1)+thirst*.3+hunger*.25-Math.min(.25,shelterKnown*.04),0,1),samples:wm.storm.samples}}
  const oldPersistent=AgentStateBoundaryV051.persistent;
  AgentStateBoundaryV051.persistent=function(a){const base=cloneJson(oldPersistent.call(this,a));base.worldModel=cloneJson(ensure(a));base.worldModelSchemaVersion=VERSION;return deepFreeze(base)};
  if(window.AstraLifeP2?.restorePersistent){const p2=window.AstraLifeP2,oldRestore=p2.restorePersistent;window.AstraLifeP2=Object.freeze({...p2,restorePersistent:(id,snapshot)=>{const result=oldRestore(id,snapshot);if(result?.ok){const a=runtime.state.agentById.get(Number(id));if(a&&snapshot?.worldModel)a.mind.worldModel=cloneJson(snapshot.worldModel);if(a)ensure(a)}return result}})}
  const oldInspector=window.updateInspector;
  if(typeof oldInspector==="function")window.updateInspector=function(){oldInspector();const a=runtime.selectedAgentId?runtime.state.agentById.get(runtime.selectedAgentId):null;if(!a||!ui.iwm)return;const wm=ensure(a),p=[...wm.predictions].reverse().find(x=>x.status==="RESOLVED");if(p)ui.iwm.textContent+=`\n\n[P3 prediction]\n${p.model} · ${p.context.loadBucket||"-"}\npred energy=${(p.predicted.energyCost||0).toFixed(4)} actual=${(p.actual.energyCost||0).toFixed(4)}\nerror=${(p.error.energyAbs||0).toFixed(4)}\nadjust ${p.adjustment.before.toFixed(3)}→${p.adjustment.after.toFixed(3)}`};
  for(const a of runtime.state.agents)ensure(a);
  window.AstraLifeP3=Object.freeze({version:VERSION,ensure:id=>{const a=runtime.state.agentById.get(Number(id));return a?cloneJson(ensure(a)):null},predictConstruction:(id,n)=>{const a=runtime.state.agentById.get(Number(id));return a?predictConstruction(runtime.state,a,n):null},predictStormRisk:id=>{const a=runtime.state.agentById.get(Number(id));return a?predictStormRisk(runtime.state,a):null}});
})();

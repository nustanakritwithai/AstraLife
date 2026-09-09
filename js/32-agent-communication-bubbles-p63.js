(() => {
  "use strict";

  const VERSION="p6.3-agent-communication-bubbles";
  const ACTIVE_MS=6200;
  const MAX_VISIBLE=10;
  const speech=new Map();
  const intentColors=Object.freeze({
    ASK:"#75c9ff",REPORT:"#7ee1b1",REQUEST_HELP:"#ffd36a",OFFER:"#d393ff",WARN:"#ff8b8b",SYNC:"#9bb7c9"
  });
  const intentLabels=Object.freeze({
    ASK:"ถาม",REPORT:"รายงาน",REQUEST_HELP:"ขอความช่วยเหลือ",OFFER:"เสนอช่วย",WARN:"เตือน",SYNC:"แชร์ข้อมูล"
  });

  const clean=(value,max)=>String(value??"").replace(/\s+/g," ").trim().slice(0,max);
  const agentName=id=>runtime.state.agentById.get(Number(id))?.name||`Astra-${String(id).padStart(3,"0")}`;

  function factSummary(fact){
    if(!fact)return "";
    const v=fact.value||{};
    if(v.type&&v.id!=null)return `${v.type} #${v.id}`;
    if(v.type)return String(v.type);
    return clean(fact.key,42);
  }

  function speechText(payload){
    const explicit=clean(payload?.text,92);
    if(explicit)return explicit;
    const first=Array.isArray(payload?.facts)?payload.facts[0]:null;
    const fact=factSummary(first);
    if(fact)return `${intentLabels[payload.intent]||payload.intent||"บอก"}: ${fact}`;
    return intentLabels[payload?.intent]||clean(payload?.intent||"สื่อสาร",40);
  }

  function targetText(recipients=[]){
    if(recipients.length===1)return agentName(recipients[0]);
    if(recipients.length>1)return `${recipients.length} agents`;
    return "nearby";
  }

  function record(agent,payload,outcome,now=performance.now()){
    if(!outcome?.ok)return null;
    const recipients=Array.isArray(outcome.recipients)?outcome.recipients.slice(0,8):[];
    const intent=clean(payload?.intent||"SYNC",24).toUpperCase();
    const entry={
      speakerId:agent.id,
      intent,
      target:targetText(recipients),
      recipients,
      text:speechText(payload),
      messageId:outcome.messageId||null,
      startedAt:now,
      expiresAt:now+ACTIVE_MS,
      source:"resolver-confirmed-share"
    };
    speech.set(agent.id,entry);
    return entry;
  }

  const oldResolveShare=ActionResolver.prototype.resolveShare;
  ActionResolver.prototype.resolveShare=function(state,agent,action){
    const outcome=oldResolveShare.call(this,state,agent,action);
    if(outcome?.ok)record(agent,action.payload||{},outcome);
    return outcome;
  };

  function activeEntry(agentId,now=performance.now()){
    const entry=speech.get(Number(agentId));
    if(!entry)return null;
    if(now>entry.expiresAt){speech.delete(Number(agentId));return null;}
    return entry;
  }

  function rounded(x,y,w,h,r=9){
    ctx.beginPath();
    if(typeof ctx.roundRect==="function")ctx.roundRect(x,y,w,h,r);
    else{
      ctx.moveTo(x+r,y);ctx.lineTo(x+w-r,y);ctx.quadraticCurveTo(x+w,y,x+w,y+r);
      ctx.lineTo(x+w,y+h-r);ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h);
      ctx.lineTo(x+r,y+h);ctx.quadraticCurveTo(x,y+h,x,y+h-r);
      ctx.lineTo(x,y+r);ctx.quadraticCurveTo(x,y,x+r,y);
    }
  }

  function wrap(text,maxChars=34){
    const words=String(text).split(/\s+/).filter(Boolean);const lines=[];let line="";
    for(const word of words){
      const next=line?`${line} ${word}`:word;
      if(next.length>maxChars&&line){lines.push(line);line=word;if(lines.length===2)break}else line=next;
    }
    if(lines.length<2&&line)lines.push(line);
    if(lines.length===2&&lines.join(" ").length<text.length)lines[1]=`${lines[1].slice(0,maxChars-2)}…`;
    return lines.slice(0,2);
  }

  function drawSpeech(agent,entry,selected=false){
    const pos=worldToScreen(visualAgentPosition(agent));
    if(!Number.isFinite(pos.x)||!Number.isFinite(pos.y))return false;
    if(pos.x<-140||pos.x>CSS_W+140||pos.y<-100||pos.y>CSS_H+100)return false;
    const header=`${entry.intent} → ${entry.target}`;
    const lines=wrap(entry.text,selected?36:32);
    ctx.save();
    ctx.font=selected?"12px system-ui":"11px system-ui";ctx.textAlign="center";ctx.textBaseline="middle";
    let width=Math.max(ctx.measureText(`💬 ${header}`).width,...lines.map(line=>ctx.measureText(line).width));
    width=Math.min(selected?235:205,Math.max(110,width+20));
    const height=lines.length>1?56:lines.length===1?44:30;
    const yOffset=selected?86:54;
    const x=clamp(pos.x-width/2,6,CSS_W-width-6);
    const y=clamp(pos.y-yOffset,6,CSS_H-height-6);
    rounded(x,y,width,height,9);
    ctx.fillStyle="#07100ef6";
    ctx.strokeStyle=intentColors[entry.intent]||"#7ee1b1";
    ctx.lineWidth=1.2;ctx.fill();ctx.stroke();
    // speech-tail points to the actual speaker
    const tailX=clamp(pos.x,x+16,x+width-16),tailY=y+height;
    ctx.beginPath();ctx.moveTo(tailX-5,tailY-1);ctx.lineTo(tailX+5,tailY-1);ctx.lineTo(clamp(pos.x,tailX-8,tailX+8),Math.min(pos.y-12,tailY+9));ctx.closePath();ctx.fillStyle="#07100ef6";ctx.fill();
    ctx.fillStyle="#ffffff";ctx.fillText(`💬 ${header}`,x+width/2,y+13,width-12);
    if(lines.length){ctx.fillStyle="#dff8e9";ctx.fillText(lines[0],x+width/2,y+30,width-12)}
    if(lines.length>1){ctx.fillStyle="#c8e7d4";ctx.fillText(lines[1],x+width/2,y+45,width-12)}
    ctx.restore();return true;
  }

  function activeRows(now=performance.now()){
    const rows=[];const selectedId=runtime.selectedAgentId;
    for(const agent of runtime.state.agents){
      if(!agent.alive)continue;
      const entry=activeEntry(agent.id,now);if(!entry)continue;
      rows.push({agent,entry,selected:agent.id===selectedId});
    }
    rows.sort((a,b)=>Number(b.selected)-Number(a.selected)||b.entry.startedAt-a.entry.startedAt);
    return rows.slice(0,MAX_VISIBLE);
  }

  function drawAll(){const rows=activeRows();for(const row of rows)drawSpeech(row.agent,row.entry,row.selected);return rows.length}

  const previousRender=window.render;
  if(typeof previousRender==="function")window.render=function(force=false){const result=previousRender(force);drawAll();return result};

  window.AstraLifeCommunicationBubbles=Object.freeze({
    version:VERSION,
    policy:"resolver-confirmed SHARE only; no fabricated receiver speech",
    isSpeaking:agentId=>!!activeEntry(agentId),
    getSpeech:agentId=>{const e=activeEntry(agentId);return e?{intent:e.intent,target:e.target,text:e.text,recipients:[...e.recipients],messageId:e.messageId}:null},
    activeSpeakerIds:()=>activeRows().map(row=>row.agent.id),
    recordForTest:(agentId,payload,outcome)=>{const agent=runtime.state.agentById.get(Number(agentId));return agent?record(agent,payload,outcome):null},
    limits:Object.freeze({activeMs:ACTIVE_MS,maxVisible:MAX_VISIBLE})
  });
})();

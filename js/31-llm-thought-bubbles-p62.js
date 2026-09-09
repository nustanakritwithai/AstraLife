(() => {
  "use strict";

  const VERSION = "p6.2-llm-thought-bubbles";
  const ACTIVE_MS = 7600;
  const POST_EXEC_MS = 3000;
  const MAX_VISIBLE = 12;
  const cache = new Map();
  const seenKeys = new Map();

  const isLlmProvider = provider => {
    const p = String(provider || "").toLowerCase();
    if(!p)return false;
    if(p === "local" || p === "astra-sim" || p === "runtime" || p.startsWith("p4"))return false;
    return p.includes("typhoon") || p === "remote" || p.includes("llm") || p.includes("provider");
  };

  const clean = (value, max) => String(value ?? "").replace(/\s+/g," ").trim().slice(0,max);

  function extractThought(response){
    if(!response || !isLlmProvider(response.provider))return null;
    const d = response.decision || {};
    const c = d.cognition || {};
    const goal = clean(c.goal, 56);
    const action = clean(d.action?.type, 18);
    const reason = clean(d.reason || c.reason, 76);
    const plan = clean(c.plan, 76);
    const detail = reason || plan;
    const parts = [];
    if(goal)parts.push(goal);
    if(action)parts.push(action);
    if(detail)parts.push(detail);
    const text = parts.join(" · ").slice(0,120);
    if(!text)return null;
    return {
      provider:String(response.provider),
      requestId:String(response.requestId || ""),
      text,
      goal,
      action,
      reason,
      plan
    };
  }

  function sourceFor(agent){
    const ready = runtime.decisionRouter.ready.get(agent.id);
    const staged = extractThought(ready?.response);
    if(staged)return {thought:staged, staged:true};
    const latest = extractThought(agent.runtime?.lastDecisionResponse);
    if(latest)return {thought:latest, staged:false};
    return null;
  }

  function refreshAgent(agent, now=performance.now()){
    const source = sourceFor(agent);
    if(!source)return null;
    const key = `${source.thought.provider}:${source.thought.requestId}:${source.thought.text}`;
    let entry = cache.get(agent.id);

    if(!entry || entry.key !== key){
      entry = {
        key,
        ...source.thought,
        staged:source.staged,
        firstSeenAt:now,
        lastStagedAt:source.staged ? now : null,
        executedAt:null
      };
      cache.set(agent.id, entry);
      seenKeys.set(agent.id, key);
    }else{
      if(source.staged){
        entry.staged = true;
        entry.lastStagedAt = now;
      }else if(entry.staged){
        entry.staged = false;
        entry.executedAt = now;
      }
    }

    const active = entry.staged ||
      (entry.executedAt != null && now-entry.executedAt <= POST_EXEC_MS) ||
      (entry.executedAt == null && now-entry.firstSeenAt <= ACTIVE_MS);
    return active ? entry : null;
  }

  function roundedBubble(x,y,w,h,r=8){
    ctx.beginPath();
    if(typeof ctx.roundRect === "function")ctx.roundRect(x,y,w,h,r);
    else{
      ctx.moveTo(x+r,y);ctx.lineTo(x+w-r,y);ctx.quadraticCurveTo(x+w,y,x+w,y+r);
      ctx.lineTo(x+w,y+h-r);ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h);
      ctx.lineTo(x+r,y+h);ctx.quadraticCurveTo(x,y+h,x,y+h-r);
      ctx.lineTo(x,y+r);ctx.quadraticCurveTo(x,y,x+r,y);
    }
  }

  function linesFor(text){
    const words = String(text).split(/\s+/).filter(Boolean);
    if(!words.length)return [];
    const lines=[];let line="";
    for(const word of words){
      const next=line?`${line} ${word}`:word;
      if(next.length>34 && line){lines.push(line);line=word;if(lines.length===2)break;}
      else line=next;
    }
    if(lines.length<2 && line)lines.push(line);
    if(lines.length>2)lines.length=2;
    if(lines.length===2 && lines.join(" ").length<text.length)lines[1]=`${lines[1].slice(0,31)}…`;
    return lines;
  }

  function drawEntry(agent, entry, selected=false){
    const pos = worldToScreen(visualAgentPosition(agent));
    if(!Number.isFinite(pos.x)||!Number.isFinite(pos.y))return false;
    if(pos.x < -120 || pos.x > CSS_W+120 || pos.y < -90 || pos.y > CSS_H+90)return false;
    const lines = linesFor(entry.text);
    if(!lines.length)return false;

    ctx.save();
    ctx.font = selected ? "12px system-ui" : "11px system-ui";
    ctx.textAlign="center";ctx.textBaseline="middle";
    let width=0;
    for(const line of lines)width=Math.max(width,ctx.measureText(line).width);
    width=Math.min(selected?220:190,Math.max(92,width+18));
    const height=lines.length===1?28:42;
    const yOffset=selected?86:54;
    const x=clamp(pos.x-width/2,6,CSS_W-width-6);
    const y=clamp(pos.y-yOffset,6,CSS_H-height-6);

    roundedBubble(x,y,width,height,9);
    ctx.fillStyle=entry.staged?"#07120df2":"#0a0f13e8";
    ctx.strokeStyle=entry.provider.includes("typhoon")?"#9f8cffdd":"#75c9ffcc";
    ctx.lineWidth=1;
    ctx.fill();ctx.stroke();

    ctx.fillStyle="#f4f1ff";
    if(lines.length===1)ctx.fillText(`💭 ${lines[0]}`,x+width/2,y+height/2,width-12);
    else{
      ctx.fillText(`💭 ${lines[0]}`,x+width/2,y+13,width-12);
      ctx.fillStyle="#d9d4ec";
      ctx.fillText(lines[1],x+width/2,y+29,width-12);
    }
    ctx.restore();
    return true;
  }

  function activeThoughts(now=performance.now()){
    const selectedId=runtime.selectedAgentId;
    const rows=[];
    for(const agent of runtime.state.agents){
      if(!agent.alive)continue;
      const entry=refreshAgent(agent,now);
      if(!entry)continue;
      rows.push({agent,entry,selected:agent.id===selectedId});
    }
    rows.sort((a,b)=>Number(b.selected)-Number(a.selected) || Number(b.entry.staged)-Number(a.entry.staged) || b.entry.firstSeenAt-a.entry.firstSeenAt);
    return rows.slice(0,MAX_VISIBLE);
  }

  function drawThoughtBubbles(){
    const rows=activeThoughts();
    for(const row of rows)drawEntry(row.agent,row.entry,row.selected);
    return rows.length;
  }

  const originalFocusedDrawer = typeof window.drawFocusedThought === "function" ? window.drawFocusedThought : null;
  if(originalFocusedDrawer)window.drawFocusedThought = () => "";

  const originalRender = window.render;
  if(typeof originalRender === "function"){
    window.render = function(force=false){
      const result=originalRender(force);
      const count=drawThoughtBubbles();
      if(count===0 && originalFocusedDrawer && runtime.selectedAgentId){
        const selected=runtime.state.agentById.get(runtime.selectedAgentId);
        if(selected)originalFocusedDrawer(selected);
      }
      return result;
    };
  }

  window.AstraLifeLLMThoughtBubbles = Object.freeze({
    version:VERSION,
    policy:"structured public summary only: goal/action/reason/plan; no hidden chain-of-thought or diagnostics",
    extractForTest:response=>extractThought(response),
    getThought:agentId=>{
      const agent=runtime.state.agentById.get(Number(agentId));
      const entry=agent&&refreshAgent(agent);
      return entry?{provider:entry.provider,requestId:entry.requestId,text:entry.text,staged:entry.staged}:null;
    },
    visibleAgentIds:()=>activeThoughts().map(row=>row.agent.id),
    limits:Object.freeze({activeMs:ACTIVE_MS,postExecMs:POST_EXEC_MS,maxVisible:MAX_VISIBLE})
  });
})();

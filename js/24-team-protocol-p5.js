(() => {
  "use strict";

  const VERSION = "p5.1";
  const TASK_STATES = Object.freeze(["PROPOSED", "RECRUITING", "READY", "IN_PROGRESS", "COMPLETED", "CANCELLED", "EXPIRED"]);
  const COMMITMENT_STATES = Object.freeze(["PROPOSED", "ACCEPTED", "DECLINED", "WITHDRAWN", "RELEASED", "COMPLETED", "EXPIRED"]);
  const RESERVATION_STATES = Object.freeze(["ACTIVE", "RELEASED", "CONSUMED"]);
  const EPSILON = 0.000001;

  const clone = value => typeof cloneJson === "function" ? cloneJson(value) : JSON.parse(JSON.stringify(value));
  const tickNow = () => Number(runtime?.state?.tick || 0);
  const taskKey = id => String(id || "");
  const commitmentKey = (taskId, agentId) => `${taskKey(taskId)}:${Number(agentId)}`;
  const reservationKey = id => String(id || "");
  const isLive = agent => !!agent && agent.alive === true;
  const finitePositive = value => Number.isFinite(Number(value)) && Number(value) > EPSILON;

  function blankProtocol(){
    return {
      version:VERSION,
      nextTask:1,
      nextCommitment:1,
      nextReservation:1,
      nextContribution:1,
      tasks:new Map(),
      commitments:new Map(),
      reservations:new Map(),
      contributions:new Map(),
      events:[]
    };
  }

  function ensureProtocol(state){
    if(!state.teamProtocol || state.teamProtocol.version !== VERSION)state.teamProtocol=blankProtocol();
    for(const agent of state.agents||[])ensureAgentCommitments(agent);
    return state.teamProtocol;
  }

  function ensureAgentCommitments(agent){
    if(!agent?.mind)return null;
    if(!agent.mind.memberCommitments || typeof agent.mind.memberCommitments !== "object" || Array.isArray(agent.mind.memberCommitments))agent.mind.memberCommitments={};
    return agent.mind.memberCommitments;
  }

  function emit(protocol, type, payload={}){
    const event={id:protocol.events.length+1,tick:tickNow(),type,...clone(payload)};
    protocol.events.push(event);
    if(protocol.events.length>200)protocol.events.splice(0,protocol.events.length-200);
    if(runtime?.events?.emit)runtime.events.emit(event.tick,`TEAM_${type}`,`Team protocol: ${type}`,payload,"important");
    return event;
  }

  function result(ok, error=null, extra={}){return {ok,...(error?{error}:{}),...clone(extra)}}

  function getAgent(agentId){return runtime?.state?.agentById?.get(Number(agentId)) || null}
  function getTask(protocol, id){return protocol.tasks.get(taskKey(id)) || null}
  function getCommitment(protocol, taskId, agentId){return protocol.commitments.get(commitmentKey(taskId,agentId)) || null}

  function activeCommitment(status){return ["PROPOSED","ACCEPTED"].includes(status)}
  function participatingCommitment(status){return ["ACCEPTED","COMPLETED"].includes(status)}

  function activeReservationTotal(protocol, resourceId, exceptId=null){
    let total=0;
    for(const reservation of protocol.reservations.values()){
      if(reservation.resourceId===Number(resourceId)&&reservation.status==="ACTIVE"&&reservation.reservationId!==exceptId)total+=reservation.amount;
    }
    return total;
  }

  function writeAgentCommitment(agent, commitment){
    const commitments=ensureAgentCommitments(agent);
    if(commitments)commitments[commitment.taskId]=clone(commitment);
  }

  function setTaskState(protocol, task, state, reason=null){
    if(task.state===state)return;
    task.state=state;task.updatedTick=tickNow();if(reason)task.lastReason=String(reason);
    emit(protocol,"TASK_STATE",{taskId:task.taskId,state,reason:reason||null});
  }

  function refreshTask(protocol, task){
    if(["COMPLETED","CANCELLED","EXPIRED"].includes(task.state))return task;
    const commitments=task.memberIds.map(id=>getCommitment(protocol,task.taskId,id)).filter(Boolean);
    const accepted=commitments.filter(c=>participatingCommitment(c.status)&&isLive(getAgent(c.agentId)));
    const required=Math.max(1,Number(task.requiredMembers)||1);
    if(task.deadlineTick!==null&&tickNow()>task.deadlineTick){expireTask(protocol,task,"deadline reached");return task}
    if(accepted.length>=required&&task.state!=="IN_PROGRESS")setTaskState(protocol,task,"READY","required members accepted");
    else if(accepted.length>0&&task.state!=="IN_PROGRESS")setTaskState(protocol,task,"RECRUITING","waiting for required members");
    else if(accepted.length<required&&task.state==="IN_PROGRESS")setTaskState(protocol,task,"RECRUITING","team membership changed");
    else if(task.state!=="IN_PROGRESS")setTaskState(protocol,task,"PROPOSED","awaiting member decisions");
    return task;
  }

  function releaseReservationInternal(protocol, reservation, reason="released"){
    if(!reservation || reservation.status!=="ACTIVE")return {changed:false,reservation};
    reservation.status="RELEASED";reservation.releasedTick=tickNow();reservation.releaseReason=reason;
    emit(protocol,"RESERVATION_RELEASED",{reservationId:reservation.reservationId,taskId:reservation.taskId,agentId:reservation.agentId,reason});
    return {changed:true,reservation};
  }

  function releaseAgentReservations(protocol, taskId, agentId, reason){
    let released=0;
    for(const reservation of protocol.reservations.values()){
      if(reservation.taskId===taskKey(taskId)&&reservation.agentId===Number(agentId)&&releaseReservationInternal(protocol,reservation,reason).changed)released++;
    }
    return released;
  }

  function expireTask(protocol, task, reason="expired"){
    if(["COMPLETED","CANCELLED","EXPIRED"].includes(task.state))return task;
    for(const commitment of protocol.commitments.values()){
      if(commitment.taskId!==task.taskId)continue;
      if(activeCommitment(commitment.status)){
        commitment.status="EXPIRED";commitment.updatedTick=tickNow();writeAgentCommitment(getAgent(commitment.agentId),commitment);
      }
    }
    for(const reservation of protocol.reservations.values())if(reservation.taskId===task.taskId)releaseReservationInternal(protocol,reservation,reason);
    setTaskState(protocol,task,"EXPIRED",reason);
    return task;
  }

  function createTask(input={}){
    const protocol=ensureProtocol(runtime.state);
    const proposerId=Number(input.proposerId), proposer=getAgent(proposerId);
    if(!isLive(proposer))return result(false,"PROPOSER_UNAVAILABLE");
    const requested=[proposerId,...(Array.isArray(input.memberIds)?input.memberIds.map(Number):[])].filter((id,i,a)=>Number.isFinite(id)&&a.indexOf(id)===i);
    const memberIds=requested.filter(id=>isLive(getAgent(id)));
    const requiredMembers=Math.max(1,Math.min(Number(input.requiredMembers)||memberIds.length,memberIds.length||1));
    const id=taskKey(input.taskId||`team-task:${runtime.state.simulationId}:${protocol.nextTask++}`);
    if(protocol.tasks.has(id))return result(false,"TASK_ID_EXISTS");
    const task={taskId:id,taskType:String(input.taskType||"COOPERATIVE_TASK"),proposerId,memberIds,requiredMembers,deadlineTick:input.deadlineTick===null||input.deadlineTick===undefined?null:Number(input.deadlineTick),state:"PROPOSED",createdTick:tickNow(),updatedTick:tickNow(),commitmentIds:[],reservationIds:[],contributionIds:[],totalContribution:0,lastReason:null};
    protocol.tasks.set(id,task);
    const proposerCommitment={commitmentId:`team-commitment:${protocol.nextCommitment++}`,taskId:id,agentId:proposerId,role:"PROPOSER",status:"ACCEPTED",createdTick:tickNow(),updatedTick:tickNow(),acceptedTick:tickNow(),withdrawnTick:null,contributionAmount:0};
    protocol.commitments.set(commitmentKey(id,proposerId),proposerCommitment);task.commitmentIds.push(proposerCommitment.commitmentId);writeAgentCommitment(proposer,proposerCommitment);
    for(const agentId of memberIds.filter(id=>id!==proposerId)){
      const commitment={commitmentId:`team-commitment:${protocol.nextCommitment++}`,taskId:id,agentId,role:"MEMBER",status:"PROPOSED",createdTick:tickNow(),updatedTick:tickNow(),acceptedTick:null,withdrawnTick:null,contributionAmount:0};
      protocol.commitments.set(commitmentKey(id,agentId),commitment);task.commitmentIds.push(commitment.commitmentId);writeAgentCommitment(getAgent(agentId),commitment);
    }
    emit(protocol,"TASK_PROPOSED",{taskId:id,proposerId,memberIds,requiredMembers,deadlineTick:task.deadlineTick});
    refreshTask(protocol,task);
    return result(true,null,{task:clone(task),commitments:memberIds.map(agentId=>clone(getCommitment(protocol,id,agentId)))})
  }

  function decideCommitment(taskId, agentId, decision){
    const protocol=ensureProtocol(runtime.state), task=getTask(protocol,taskId), agent=getAgent(agentId), commitment=getCommitment(protocol,taskId,agentId);
    if(!task||!commitment)return result(false,"COMMITMENT_NOT_FOUND");
    if(!isLive(agent)&&decision==="ACCEPTED")return result(false,"MEMBER_UNAVAILABLE");
    if(["COMPLETED","CANCELLED","EXPIRED"].includes(task.state))return result(false,"TASK_TERMINAL");
    if(task.deadlineTick!==null&&tickNow()>task.deadlineTick)return result(false,"TASK_EXPIRED");
    if(commitment.status===decision)return result(true,null,{idempotent:true,task:clone(task),commitment:clone(commitment)});
    if(!["PROPOSED","DECLINED","WITHDRAWN","RELEASED"].includes(commitment.status))return result(false,"INVALID_COMMITMENT_TRANSITION");
    commitment.status=decision;commitment.updatedTick=tickNow();
    if(decision==="ACCEPTED")commitment.acceptedTick=tickNow();
    writeAgentCommitment(agent,commitment);emit(protocol,decision==="ACCEPTED"?"COMMITMENT_ACCEPTED":"COMMITMENT_DECLINED",{taskId:task.taskId,agentId});refreshTask(protocol,task);
    return result(true,null,{task:clone(task),commitment:clone(commitment)})
  }

  function withdraw(taskId, agentId, reason="member withdrew"){
    const protocol=ensureProtocol(runtime.state),task=getTask(protocol,taskId),agent=getAgent(agentId),commitment=getCommitment(protocol,taskId,agentId);
    if(!task||!commitment)return result(false,"COMMITMENT_NOT_FOUND");
    if(commitment.status==="WITHDRAWN"||commitment.status==="RELEASED")return result(true,null,{idempotent:true,released:0,task:clone(task),commitment:clone(commitment)});
    if(["COMPLETED","CANCELLED","EXPIRED"].includes(task.state))return result(false,"TASK_TERMINAL");
    commitment.status="WITHDRAWN";commitment.withdrawnTick=tickNow();commitment.updatedTick=tickNow();writeAgentCommitment(agent,commitment);
    const released=releaseAgentReservations(protocol,taskId,agentId,reason);emit(protocol,"COMMITMENT_WITHDRAWN",{taskId:task.taskId,agentId,reason,released});refreshTask(protocol,task);
    return result(true,null,{released,task:clone(task),commitment:clone(commitment)})
  }

  function markUnavailable(agentId, reason="member unavailable"){
    const protocol=ensureProtocol(runtime.state),changed=[];
    for(const task of protocol.tasks.values()){
      const c=getCommitment(protocol,task.taskId,agentId);
      if(c&&activeCommitment(c.status))changed.push(withdraw(task.taskId,agentId,reason));
    }
    return result(true,null,{agentId:Number(agentId),changed})
  }

  function startTask(taskId){
    const protocol=ensureProtocol(runtime.state),task=getTask(protocol,taskId);
    if(!task)return result(false,"TASK_NOT_FOUND");
    refreshTask(protocol,task);
    if(task.state==="IN_PROGRESS")return result(true,null,{idempotent:true,task:clone(task)});
    if(task.state!=="READY")return result(false,"TASK_NOT_READY",{task:clone(task)});
    setTaskState(protocol,task,"IN_PROGRESS","explicit start");return result(true,null,{task:clone(task)})
  }

  function reserveResource(input={}){
    const protocol=ensureProtocol(runtime.state),task=getTask(protocol,input.taskId),agent=getAgent(input.agentId),resource=runtime.state.resourceById.get(Number(input.resourceId));
    if(!task||!agent||!resource)return result(false,"RESERVATION_TARGET_NOT_FOUND");
    if(!isLive(agent))return result(false,"MEMBER_UNAVAILABLE");
    const commitment=getCommitment(protocol,task.taskId,agent.id);
    if(!commitment||!participatingCommitment(commitment.status))return result(false,"MEMBER_NOT_COMMITTED");
    const amount=Number(input.amount),semantics=String(input.semantics||"DIVISIBLE").toUpperCase();
    if(!finitePositive(amount))return result(false,"INVALID_AMOUNT");
    if(!["DIVISIBLE","INDIVISIBLE"].includes(semantics))return result(false,"INVALID_RESOURCE_SEMANTICS");
    if(semantics==="INDIVISIBLE"&&!Number.isInteger(amount))return result(false,"INDIVISIBLE_AMOUNT_MUST_BE_INTEGER");
    const id=reservationKey(input.reservationId||`team-reservation:${protocol.nextReservation++}`);
    const existing=protocol.reservations.get(id);if(existing)return result(true,null,{idempotent:true,reservation:clone(existing)});
    const available=Number(resource.amount)-activeReservationTotal(protocol,resource.id);
    if(amount>available+EPSILON)return result(false,"INSUFFICIENT_UNRESERVED_RESOURCE",{available:Math.max(0,available),requested:amount,resourceId:resource.id});
    const reservation={reservationId:id,taskId:task.taskId,agentId:agent.id,resourceId:resource.id,amount,semantics,status:"ACTIVE",createdTick:tickNow(),releasedTick:null,releaseReason:null};
    protocol.reservations.set(id,reservation);task.reservationIds.push(id);emit(protocol,"RESOURCE_RESERVED",{reservationId:id,taskId:task.taskId,agentId:agent.id,resourceId:resource.id,amount,semantics});
    return result(true,null,{reservation:clone(reservation),availableAfter:Math.max(0,available-amount)})
  }

  function releaseReservation(reservationId, reason="released"){
    const protocol=ensureProtocol(runtime.state),reservation=protocol.reservations.get(reservationKey(reservationId));
    if(!reservation)return result(false,"RESERVATION_NOT_FOUND");
    const changed=releaseReservationInternal(protocol,reservation,reason).changed;return result(true,null,{idempotent:!changed,reservation:clone(reservation)})
  }

  function commitReservation(reservationId){
    const protocol=ensureProtocol(runtime.state),reservation=protocol.reservations.get(reservationKey(reservationId));
    if(!reservation)return result(false,"RESERVATION_NOT_FOUND");
    if(reservation.status!=="ACTIVE")return result(true,null,{idempotent:true,reservation:clone(reservation)});
    const resource=runtime.state.resourceById.get(reservation.resourceId);
    if(!resource||resource.amount+EPSILON<reservation.amount){releaseReservationInternal(protocol,reservation,"resource changed before commit");return result(false,"RESOURCE_CHANGED_BEFORE_COMMIT");}
    resource.amount=Math.max(0,resource.amount-reservation.amount);reservation.status="CONSUMED";reservation.consumedTick=tickNow();emit(protocol,"RESOURCE_CONSUMED",{reservationId:reservation.reservationId,resourceId:resource.id,amount:reservation.amount});return result(true,null,{reservation:clone(reservation),remaining:resource.amount})
  }

  function recordContribution(input={}){
    const protocol=ensureProtocol(runtime.state),task=getTask(protocol,input.taskId),agent=getAgent(input.agentId);
    if(!task||!agent)return result(false,"CONTRIBUTION_TARGET_NOT_FOUND");
    const commitment=getCommitment(protocol,task.taskId,agent.id);
    if(!commitment||!participatingCommitment(commitment.status))return result(false,"MEMBER_NOT_COMMITTED");
    if(!["READY","IN_PROGRESS"].includes(task.state))return result(false,"TASK_NOT_ACTIVE");
    const actionId=String(input.actionId||"");if(!actionId)return result(false,"ACTION_ID_REQUIRED");
    const id=`${task.taskId}:${agent.id}:${actionId}`,existing=protocol.contributions.get(id);
    if(existing)return result(true,null,{idempotent:true,contribution:clone(existing),task:clone(task)});
    const amount=Math.max(0,Number(input.amount)||0),contribution={contributionId:`team-contribution:${protocol.nextContribution++}`,dedupeKey:id,taskId:task.taskId,agentId:agent.id,actionId,actionType:String(input.actionType||"TEAM_ACTION"),amount,confirmedTick:tickNow()};
    protocol.contributions.set(id,contribution);task.contributionIds.push(contribution.contributionId);task.totalContribution+=amount;commitment.contributionAmount+=amount;commitment.updatedTick=tickNow();writeAgentCommitment(agent,commitment);emit(protocol,"CONTRIBUTION_CONFIRMED",{taskId:task.taskId,agentId:agent.id,actionId,amount});return result(true,null,{contribution:clone(contribution),task:clone(task)})
  }

  function completeTask(taskId){
    const protocol=ensureProtocol(runtime.state),task=getTask(protocol,taskId);
    if(!task)return result(false,"TASK_NOT_FOUND");
    if(task.state==="COMPLETED")return result(true,null,{idempotent:true,task:clone(task)});
    if(task.state!=="IN_PROGRESS")return result(false,"TASK_NOT_IN_PROGRESS");
    for(const c of protocol.commitments.values())if(c.taskId===task.taskId&&c.status==="ACCEPTED"){c.status="COMPLETED";c.updatedTick=tickNow();writeAgentCommitment(getAgent(c.agentId),c)}
    setTaskState(protocol,task,"COMPLETED","explicit completion");return result(true,null,{task:clone(task)})
  }

  function expire(tick=tickNow()){
    const protocol=ensureProtocol(runtime.state),expired=[];
    const target=Number(tick);for(const task of protocol.tasks.values())if(task.deadlineTick!==null&&target>task.deadlineTick&&!['COMPLETED','CANCELLED','EXPIRED'].includes(task.state)){expired.push(expireTask(protocol,task,"deadline reached"));}
    return result(true,null,{count:expired.length,tasks:expired.map(clone)})
  }

  function serialise(protocol){
    return {version:VERSION,tasks:[...protocol.tasks.values()].map(clone),commitments:[...protocol.commitments.values()].map(clone),reservations:[...protocol.reservations.values()].map(clone),contributions:[...protocol.contributions.values()].map(clone),events:protocol.events.slice(-100).map(clone)}
  }

  function integrity(){
    const protocol=ensureProtocol(runtime.state),errors=[],activeByResource=new Map();
    for(const reservation of protocol.reservations.values())if(reservation.status==="ACTIVE")activeByResource.set(reservation.resourceId,(activeByResource.get(reservation.resourceId)||0)+reservation.amount);
    for(const resource of runtime.state.resources){const reserved=activeByResource.get(resource.id)||0;if(resource.amount<-.001)errors.push(`resource ${resource.id} negative`);if(reserved>resource.amount+EPSILON)errors.push(`resource ${resource.id} over-reserved`)}
    for(const task of protocol.tasks.values()){
      if(!TASK_STATES.includes(task.state))errors.push(`task ${task.taskId} invalid state`);
      for(const id of task.reservationIds){const r=protocol.reservations.get(id);if(!r)errors.push(`task ${task.taskId} missing reservation ${id}`)}
    }
    for(const c of protocol.contributions.values())if(protocol.contributions.get(c.dedupeKey)!==c)errors.push(`duplicate contribution ${c.dedupeKey}`);
    for(const reservation of protocol.reservations.values())if(!RESERVATION_STATES.includes(reservation.status))errors.push(`reservation ${reservation.reservationId} invalid state`);
    return {ok:errors.length===0,errors}
  }

  const oldReset=WorldRuntime.prototype.reset;
  WorldRuntime.prototype.reset=function(seed=this.seed){const output=oldReset.call(this,seed);ensureProtocol(this.state);return output};
  const oldSnapshot=WorldRuntime.prototype.snapshot;
  WorldRuntime.prototype.snapshot=function(){const snapshot=oldSnapshot.call(this);const protocol=ensureProtocol(this.state);snapshot.teamProtocol=serialise(protocol);for(const row of snapshot.agents){const agent=this.state.agentById.get(row.id);row.mind.memberCommitments=clone(agent?.mind?.memberCommitments||{})}return snapshot};
  if(typeof AgentStateBoundaryV051!=="undefined"){
    const oldPersistent=AgentStateBoundaryV051.persistent;
    AgentStateBoundaryV051.persistent=function(agent){const snapshot=clone(oldPersistent.call(this,agent));snapshot.memberCommitments=clone(agent?.mind?.memberCommitments||{});snapshot.teamCommitmentsSchemaVersion=VERSION;return deepFreeze(snapshot)};
  }

  ensureProtocol(runtime.state);
  window.AstraLifeP5=Object.freeze({
    version:VERSION,
    taskStates:TASK_STATES.slice(),commitmentStates:COMMITMENT_STATES.slice(),reservationStates:RESERVATION_STATES.slice(),
    reset:()=>{runtime.state.teamProtocol=blankProtocol();for(const agent of runtime.state.agents)ensureAgentCommitments(agent);return serialise(runtime.state.teamProtocol)},
    proposeTask:createTask,
    accept:(taskId,agentId)=>decideCommitment(taskId,agentId,"ACCEPTED"),
    decline:(taskId,agentId)=>decideCommitment(taskId,agentId,"DECLINED"),
    withdraw,
    markUnavailable,
    startTask,
    completeTask,
    expire,
    reserveResource,
    releaseReservation,
    commitReservation,
    recordContribution,
    getTask:id=>{const t=getTask(ensureProtocol(runtime.state),id);return t?clone(t):null},
    getCommitment:(taskId,agentId)=>{const c=getCommitment(ensureProtocol(runtime.state),taskId,agentId);return c?clone(c):null},
    getAgentCommitments:id=>clone(getAgent(Number(id))?.mind?.memberCommitments||{}),
    snapshot:()=>serialise(ensureProtocol(runtime.state)),
    selfTest:()=>{const base=runtime.selfTest();const protocol=integrity();return {ok:base.ok&&protocol.ok,errors:[...base.errors,...protocol.errors],base,protocol}}
  });
})();

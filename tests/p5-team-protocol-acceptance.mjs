import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeP5&&window.AstraLifeP4);
  const result=await page.evaluate(()=>{
    AstraColony.reset('P5.1-TEAM-PROTOCOL-20260908');
    runtime.state.running=false;
    const p5=window.AstraLifeP5;
    const [proposer,member,competitor]=runtime.state.agents.slice(0,3);
    const resource=runtime.state.resources.find(r=>r.type==='berry');
    resource.amount=1;
    const originalGoal=member.mind.goal;
    const proposal=p5.proposeTask({taskId:'team:p5:withdraw',taskType:'carry-water',proposerId:proposer.id,memberIds:[member.id],requiredMembers:2,deadlineTick:20});
    const accepted=p5.accept('team:p5:withdraw',member.id);
    const started=p5.startTask('team:p5:withdraw');
    const firstReserve=p5.reserveResource({taskId:'team:p5:withdraw',agentId:member.id,resourceId:resource.id,amount:1,semantics:'INDIVISIBLE',reservationId:'reserve:withdraw'});
    const withdrawn=p5.withdraw('team:p5:withdraw',member.id,'member left team');
    const duplicateWithdraw=p5.withdraw('team:p5:withdraw',member.id,'duplicate withdrawal');
    const afterWithdraw=p5.getTask('team:p5:withdraw');

    const actProposal=p5.proposeTask({taskId:'team:p5:act',taskType:'last-resource',proposerId:proposer.id,memberIds:[competitor.id],requiredMembers:2,deadlineTick:30});
    p5.accept('team:p5:act',competitor.id);
    p5.startTask('team:p5:act');
    const reserveA=p5.reserveResource({taskId:'team:p5:act',agentId:proposer.id,resourceId:resource.id,amount:1,semantics:'INDIVISIBLE',reservationId:'reserve:a'});
    const reserveB=p5.reserveResource({taskId:'team:p5:act',agentId:competitor.id,resourceId:resource.id,amount:1,semantics:'INDIVISIBLE',reservationId:'reserve:b'});
    const commitA=p5.commitReservation('reserve:a');
    const commitADuplicate=p5.commitReservation('reserve:a');
    const contribution=p5.recordContribution({taskId:'team:p5:act',agentId:proposer.id,actionId:'action:confirmed:1',actionType:'GATHER',amount:1});
    const contributionDuplicate=p5.recordContribution({taskId:'team:p5:act',agentId:proposer.id,actionId:'action:confirmed:1',actionType:'GATHER',amount:1});

    const deadMember=runtime.state.agents[3];
    const deadResource=runtime.state.resources.find(r=>r.type==='berry'&&r.id!==resource.id);
    deadResource.amount=1;
    const deadProposal=p5.proposeTask({taskId:'team:p5:dead',taskType:'dead-member',proposerId:proposer.id,memberIds:[deadMember.id],requiredMembers:2,deadlineTick:50});
    p5.accept('team:p5:dead',deadMember.id);
    p5.startTask('team:p5:dead');
    p5.reserveResource({taskId:'team:p5:dead',agentId:deadMember.id,resourceId:deadResource.id,amount:1,semantics:'INDIVISIBLE',reservationId:'reserve:dead'});
    deadMember.alive=false;
    const unavailable=p5.markUnavailable(deadMember.id,'member died');
    const unavailableDuplicate=p5.markUnavailable(deadMember.id,'duplicate death event');
    deadMember.alive=true;

    const timeoutMember=runtime.state.agents[4];
    const timeoutResource=runtime.state.resources.find(r=>r.type==='berry'&&r.id!==resource.id&&r.id!==deadResource.id);
    timeoutResource.amount=1;
    const timeoutProposal=p5.proposeTask({taskId:'team:p5:timeout',taskType:'timeout-member',proposerId:proposer.id,memberIds:[timeoutMember.id],requiredMembers:2,deadlineTick:60});
    p5.accept('team:p5:timeout',timeoutMember.id);
    p5.startTask('team:p5:timeout');
    p5.reserveResource({taskId:'team:p5:timeout',agentId:timeoutMember.id,resourceId:timeoutResource.id,amount:1,semantics:'INDIVISIBLE',reservationId:'reserve:timeout'});
    runtime.state.tick=61;
    const expired=p5.expire(61);
    const expiredDuplicate=p5.expire(61);
    const snapshot=runtime.snapshot();
    const check=p5.selfTest();
    const tests={
      proposalCreated:proposal.ok&&proposal.task.state==='RECRUITING',
      explicitAcceptAndReady:accepted.ok&&started.ok,
      team01WithdrawalReleasesReservation:withdrawn.ok&&withdrawn.released===1&&afterWithdraw.state==='RECRUITING'&&p5.snapshot().reservations.find(r=>r.reservationId==='reserve:withdraw').status==='RELEASED',
      team01WithdrawalIsIdempotent:duplicateWithdraw.ok&&duplicateWithdraw.idempotent===true&&duplicateWithdraw.released===0,
      act01FirstReservationWins:reserveA.ok&&!reserveB.ok&&reserveB.error==='INSUFFICIENT_UNRESERVED_RESOURCE',
      act01NeverNegative:commitA.ok&&commitADuplicate.idempotent===true&&resource.amount===0,
      contributionDeduped:contribution.ok&&contributionDuplicate.idempotent===true&&p5.getTask('team:p5:act').totalContribution===1,
      team02DeadMemberReleasesOnce:deadProposal.ok&&unavailable.ok&&unavailable.changed.length===1&&unavailable.changed[0].released===1&&unavailableDuplicate.ok&&unavailableDuplicate.changed.length===0&&p5.snapshot().reservations.find(r=>r.reservationId==='reserve:dead').status==='RELEASED',
      team02TimeoutReleasesOnce:timeoutProposal.ok&&expired.ok&&expired.count>=1&&expired.tasks.some(task=>task.taskId==='team:p5:timeout')&&expiredDuplicate.ok&&expiredDuplicate.count===0&&p5.getCommitment('team:p5:timeout',timeoutMember.id).status==='EXPIRED'&&p5.snapshot().reservations.find(r=>r.reservationId==='reserve:timeout').status==='RELEASED',
      goalsUntouched:member.mind.goal===originalGoal,
      memberCommitmentsPersisted:!!snapshot.agents.find(a=>a.id===member.id)?.mind?.memberCommitments?.['team:p5:withdraw'],
      protocolIntegrity:check.ok&&runtime.selfTest().ok
    };
    return {ok:Object.values(tests).every(Boolean),tests,proposal,accepted,started,firstReserve,withdrawn,duplicateWithdraw,reserveA,reserveB,commitA,commitADuplicate,contribution,contributionDuplicate,unavailable,unavailableDuplicate,expired,expiredDuplicate,check,resource:snapshot.resources.find(r=>r.id===resource.id)};
  });
  console.log(JSON.stringify(result,null,2));
  if(!result.ok)process.exitCode=1;
}finally{await browser.close()}

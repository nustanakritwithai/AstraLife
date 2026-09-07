import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage();
  await page.goto(pathToFileURL(path.resolve('index.html')).href);
  await page.waitForFunction(()=>window.AstraLifeP4&&window.AstraLifeP1&&window.AstraLifeV051);
  const result=await page.evaluate(()=>{
    runtime.state.running=false;
    runtime.reset('P4.1-CAPABILITIES-20260907');
    runtime.state.running=false;
    const state=runtime.state,[A,B,C,D]=state.agents.slice(0,4);
    const camp=state.camp;
    const park=(a,x=camp.x,y=camp.y)=>{a.role='human';a.alive=true;a.body.x=x;a.body.y=y;a.body.energy=95;a.body.hp=100;a.inventory={type:null,amount:0};a.mind.executablePlan=null;a.mind.planBudget=null};
    [A,B,C,D].forEach(a=>park(a));
    const requestFor=(a,obs)=>runtime.requestFactory.build(state,a,obs,'local');
    const responseFor=(req,action,goal)=>makeDecisionResponse(req,'local',action,{goal,reason:'P4.1 acceptance',plan:`${action.type} under observable preconditions`},.8,12,{test:'P4.1'});
    const accept=(a,action)=>{
      const obs=runtime.observer.capture(state,a),req=requestFor(a,obs),response=responseFor(req,action,action.type.toLowerCase()),checked=runtime.validator.validate(response,req,state),q=new ActionQueue();
      if(checked.ok)runtime.decisionRouter.applyAccepted(state,{agent:a,observation:obs,request:req,providerId:'local',rawResponse:response},checked.normalized,q,false);
      return {obs,req,response,checked,queued:q.drain()};
    };

    // CAP-01: a Human/generalist can propose and pass BUILD gates.
    state.stock.wood=50;camp.construction={active:false,progress:0,startedTick:0,crew:[]};
    A.emergentRole='generalist';B.emergentRole='generalist';
    const buildA=accept(A,{type:ACTION.BUILD,payload:{}}),buildB=accept(B,{type:ACTION.BUILD,payload:{}});
    const buildOut=runtime.resolver.resolve(state,[...buildA.queued,...buildB.queued]);
    const cap01=buildA.checked.ok&&buildB.checked.ok&&buildA.req.agent.role==='human'&&buildA.req.agent.capabilities.canBuild&&buildA.queued[0]?.type===ACTION.BUILD&&buildOut.filter(o=>o.ok).length===2&&camp.construction.progress>0;

    // CAP-02: a Human/generalist can propose and pass HEAL gates.
    park(C,camp.x,camp.y);park(D,camp.x,camp.y);C.emergentRole='generalist';D.emergentRole='generalist';D.body.hp=40;state.stock.medicine=0;
    const heal=accept(C,{type:ACTION.HEAL,payload:{targetAgentId:D.id}});
    const hpBefore=D.body.hp,healOut=runtime.resolver.resolve(state,heal.queued),cap02=heal.checked.ok&&heal.req.agent.role==='human'&&heal.req.agent.capabilities.canHeal&&heal.queued[0]?.type===ACTION.HEAL&&healOut[0]?.ok&&D.body.hp>hpBefore;

    // CAP-03: skill changes effectiveness, never permission.
    park(A,camp.x,camp.y);park(B,camp.x,camp.y);A.development.skills.medicine.competency=.1;B.development.skills.medicine.competency=.9;A.emergentRole='generalist';B.emergentRole='generalist';C.body.hp=40;D.body.hp=40;state.stock.medicine=0;
    const low=accept(A,{type:ACTION.HEAL,payload:{targetAgentId:C.id}}),high=accept(B,{type:ACTION.HEAL,payload:{targetAgentId:D.id}});
    const lowBefore=C.body.hp,highBefore=D.body.hp,skillOut=runtime.resolver.resolve(state,[...low.queued,...high.queued]);
    const lowDelta=C.body.hp-lowBefore,highDelta=D.body.hp-highBefore;
    const cap03=low.checked.ok&&high.checked.ok&&skillOut.every(o=>o.ok)&&lowDelta>0&&highDelta>lowDelta&&A.role==='human'&&B.role==='human';

    // BEL-03: full inventory is an actor constraint, not target-unavailable evidence.
    park(A);A.emergentRole='generalist';A.inventory={type:'food',amount:A.capacity};
    const resource=state.resources.find(r=>r.type==='berry'&&r.amount>2);A.body.x=resource.x;A.body.y=resource.y;
    const key=`resource:${resource.id}`;runtime.memory.setFact(A,key,{id:resource.id,type:resource.type,x:resource.x,y:resource.y,amountBand:'high'},.95,'direct');
    const beforeBelief=AstraLifeP1.activeFor(A.id,key),gather=accept(A,{type:ACTION.GATHER,payload:{resourceId:resource.id,resourceType:'berry',carryType:'food'}});
    const afterBelief=AstraLifeP1.activeFor(A.id,key),bel03=gather.queued[0]?.type===ACTION.WAIT&&A.mind.facts.has(key)&&afterBelief?.status===beforeBelief?.status;

    const tests={CAP01_generalistBuild:cap01,CAP02_generalistHeal:cap02,CAP03_skillChangesEffectivenessNotPermission:cap03,BEL03_inventoryFullDoesNotStaleResourceBelief:bel03,baseRolesRemainHuman:[A,B,C,D].every(a=>a.role==='human')};
    return {ok:Object.values(tests).every(Boolean),tests,observations:{lowDelta,highDelta,beforeBeliefStatus:beforeBelief?.status,afterBeliefStatus:afterBelief?.status,gatherOk:gather.checked.ok,queued:gather.queued.map(x=>x.type),factStillPresent:A.mind.facts.has(key)},integrity:runtime.selfTest()};
  });
  console.log(JSON.stringify(result,null,2));
  if(!result.ok)process.exitCode=1;
}finally{await browser.close()}

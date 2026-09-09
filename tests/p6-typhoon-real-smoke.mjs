import { spawn } from 'node:child_process';

const key = process.env.OPENTYPHOON_API_KEY;
if(!key){
  console.error('OPENTYPHOON_API_KEY is required for the real-provider smoke test.');
  process.exit(2);
}

const port = Number(process.env.P6_SMOKE_PORT || 18787);
const child = spawn(process.execPath, ['server/typhoon-bridge.mjs'], {
  stdio:['ignore','pipe','pipe'],
  env:{...process.env, PORT:String(port), ASTRALIFE_ALLOWED_ORIGINS:'*'}
});
let logs = '';
child.stdout.on('data', chunk => { logs += chunk; });
child.stderr.on('data', chunk => { logs += chunk; });

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const deadline = Date.now() + 5000;
let ready = false;
while(Date.now() < deadline){
  try{
    const health = await fetch(`http://127.0.0.1:${port}/health`).then(r => r.json());
    if(health.ok && health.configured){ ready = true; break; }
  }catch{}
  await sleep(100);
}
if(!ready){ child.kill('SIGTERM'); throw new Error(`bridge did not become ready\n${logs}`); }

const request = {
  protocol:'astra-colony.decision-request.v1',
  requestId:'p6-real-smoke:1:1',
  sessionId:'p6-real-smoke:agent-1',
  simulation:{id:'p6-real-smoke',seed:'P6-REAL',tick:1,day:1,alive:1,providerHint:'typhoon'},
  agent:{id:1,name:'Astra-001',role:'human',capacity:3,capabilities:{canBuild:true,canHeal:true,canScout:false,canCarry:false}},
  observation:{
    protocol:'astra-colony.observation.v1',tick:1,self:{x:100,y:100,hp:100,hunger:10,thirst:10,energy:90,carry:{type:null,amount:0}},
    camp:{visible:true,x:100,y:100,distance:0,stock:{food:20,water:20,wood:10,medicine:2},shelter:1},
    visibleResources:[],nearbyAgents:[],messages:[]
  },
  memory:{currentGoal:'orient',goalReason:'smoke test',currentPlan:'OBSERVE → ACT',beliefStock:{food:20,water:20,wood:10,medicine:2},knownShelters:1,failedActions:0,newFactKeys:[],symbolicFacts:[],recentEpisodes:[],social:{}},
  actionContract:{protocol:'astra-colony.action.v1',allowedTypes:['MOVE','REST','WAIT'],worldBounds:{minX:4,maxX:996,minY:4,maxY:696},limits:{},rule:'Return one action only.'},
  identity:{simulationId:'p6-real-smoke',runEpoch:1,agentId:1,sessionId:'p6-real-smoke:agent-1',requestId:'p6-real-smoke:1:1',observationId:'obs:p6-real-smoke:1:1',deadlineTick:9},
  providerBudget:{maxOutputTokens:320,maxInputTokens:4000,timeoutMs:9000,retryLimit:1}
};

try{
  const response = await fetch(`http://127.0.0.1:${port}/decide`, {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(request)});
  const body = await response.json();
  if(!response.ok) throw new Error(`bridge HTTP ${response.status}: ${JSON.stringify(body)}`);
  if(body.provider !== 'typhoon') throw new Error(`provider mismatch: ${body.provider}`);
  if(body.identity?.sessionId !== request.identity.sessionId) throw new Error('session identity mismatch');
  if(body.diagnostics?.actualProvider !== 'opentyphoon') throw new Error('actual provider not recorded');
  if(!String(body.diagnostics?.model || '').includes('typhoon')) throw new Error(`unexpected model: ${body.diagnostics?.model}`);
  if(!request.actionContract.allowedTypes.includes(body.decision?.action?.type)) throw new Error(`model proposed disallowed action: ${body.decision?.action?.type}`);
  console.log('P6 real Typhoon smoke PASS');
  console.log(JSON.stringify({provider:body.provider,actualProvider:body.diagnostics.actualProvider,model:body.diagnostics.model,usage:body.diagnostics.usage,action:body.decision.action.type},null,2));
} finally {
  child.kill('SIGTERM');
}

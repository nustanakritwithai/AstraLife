"use strict";

const DECISION_STATUS_V051=Object.freeze({PROPOSED:"PROPOSED",VALIDATING:"VALIDATING",ACCEPTED:"ACCEPTED",REJECTED:"REJECTED",EXPIRED:"EXPIRED",RESOLVED:"RESOLVED"});

class DecisionStagingV051{
  constructor(limit=3000){this.limit=limit;this.items=[];this.byId=new Map();this.nextId=1}
  makeId(agentId,tick){return `dec-${String(agentId).padStart(3,"0")}-${tick}-${this.nextId++}`}
  propose({agentId,sessionId,tick,providerId,providerVersion="v1",observationId,requestedAction,rawResponse=null}){
    const entry={protocol:ASTRA_CORE_PROTOCOLS_V051.decision,decisionId:this.makeId(agentId,tick),agentId,sessionId,tick,providerId,providerVersion,observationId,requestedAction:cloneJson(requestedAction||{}),status:DECISION_STATUS_V051.PROPOSED,validationResults:[],rejectionReason:null,feedback:null,createdAtTick:tick,resolvedAtTick:null,rawResponse};
    this.items.push(entry);this.byId.set(entry.decisionId,entry);if(this.items.length>this.limit){const old=this.items.shift();this.byId.delete(old.decisionId)}return entry;
  }
  transition(id,status,patch={}){const e=this.byId.get(id);if(!e)return null;Object.assign(e,patch,{status});return e}
  validating(id){return this.transition(id,DECISION_STATUS_V051.VALIDATING)}
  accept(id,validationResults=[]){return this.transition(id,DECISION_STATUS_V051.ACCEPTED,{validationResults:cloneJson(validationResults),rejectionReason:null})}
  reject(id,reason,message,tick,validationResults=[]){const feedback=Object.freeze({decisionId:id,status:DECISION_STATUS_V051.REJECTED,reason:String(reason||"VALIDATION_REJECTED"),message:String(message||reason||"Decision rejected"),worldTick:tick});return this.transition(id,DECISION_STATUS_V051.REJECTED,{validationResults:cloneJson(validationResults),rejectionReason:feedback.reason,feedback})}
  resolve(id,tick,outcome){return this.transition(id,DECISION_STATUS_V051.RESOLVED,{resolvedAtTick:tick,outcome:outcome?cloneJson(outcome):null})}
  expire(id,tick,reason="STALE_DECISION"){return this.transition(id,DECISION_STATUS_V051.EXPIRED,{resolvedAtTick:tick,rejectionReason:reason})}
  recent(count=100){return this.items.slice(-count).map(x=>cloneJson(x))}
  unresolved(){return this.items.filter(x=>![DECISION_STATUS_V051.REJECTED,DECISION_STATUS_V051.EXPIRED,DECISION_STATUS_V051.RESOLVED].includes(x.status))}
}

(() => {
  "use strict";

  // P0.1 legacy ingest still routes message facts through setFact().
  // P1 then ingests the same delivered message again via receiveBelief(),
  // which can create a fallback-origin belief before the provenance-aware one.
  // Suppress only that legacy message setFact path while P1 ingest runs.
  const p1SetFact=MemorySystem.prototype.setFact;
  MemorySystem.prototype.setFact=function(a,key,value,confidence,source="direct",sourceAgentId=null){
    if(this._p1SuppressLegacyMessageSetFact&&source==="message")return null;
    return p1SetFact.call(this,a,key,value,confidence,source,sourceAgentId);
  };

  const p1Ingest=MemorySystem.prototype.ingest;
  MemorySystem.prototype.ingest=function(a,o,state=null){
    const previous=!!this._p1SuppressLegacyMessageSetFact;
    this._p1SuppressLegacyMessageSetFact=true;
    try{return p1Ingest.call(this,a,o,state)}
    finally{this._p1SuppressLegacyMessageSetFact=previous}
  };
})();

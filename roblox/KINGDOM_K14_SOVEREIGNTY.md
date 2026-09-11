# K14 Faction / Sovereignty

Shadow sovereignty registry for Kingdom systems.

Server API under `ServerScriptService/AstraKingdom/K14SovereigntyApi`:
- EnsureFaction
- SetRuler
- SetTreasuryRef
- ClaimSettlement
- ReleaseSettlement
- SetVassal
- ReleaseVassal
- GetFaction
- GetClaim
- GetSnapshot

K14 records faction/ruler/claim/vassal/tribute relationships only inside Kingdom state. It does not mutate real settlement ownership, Agent Role/Goal/Skill, Colony stock, combat or WorldSim state.

This makes sovereignty data composable before an authoritative settlement-ownership handoff is defined.

# K13 Diplomacy & Treaties

Server-owned treaty state machine for Kingdom systems.

Supported treaty types:
- trade
- alliance
- peace
- tribute
- embargo

Lifecycle:
`proposed -> active -> broken/expired`

API under `ServerScriptService/AstraKingdom/K13DiplomacyApi`:
- Propose
- Activate
- Break
- GetTreaty
- GetSnapshot

K13 owns only treaty state inside Kingdom. It never writes Agent Role/Goal/Skill, stock, WorldSim state, settlement ownership or combat state.

# K8 Trade Contracts

Read-only trade-opportunity engine derived from Kingdom-sandbox economics.

## Inputs
- optional `Workspace.AstraSettlements` records
- authoritative colony stock through K0 SourceReader fallback
- optional route cost/risk attributes from `AstraLivingWorldState`

## Outputs
`Workspace.AstraKingdomState/K8TradeContracts`

Publishes proposal counts, viable trade count, expected profit and the top contract/good.

## Boundaries
- never mutates stock
- never creates routes or pathfinding
- never moves Agents
- never changes Role/Goal/Skill
- WorldSim remains authoritative for route/navigation risk

## Integration contract
Future settlement systems can expose attributes:
`SettlementId`, `Population`, `Stock_*`, `Price_*`, `Target_*`.

K8 will consume them without requiring a rewrite.

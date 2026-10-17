# SurvivalCrafting S0 Core

Isolated plug-in foundation for survival gathering, items, crafting, stations, building parts and durability.

## Ownership boundary

SurvivalCrafting does not own WorldClock, WorldGrid, Living World resources/transactions, navigation, Agent movement/goals/roles/skills, legacy Inventory, legacy Construction or combat.

WorldSim W0-W7 remains authoritative for physical world/resource truth. P7+ remains authoritative for Agent cognition/learning. Existing ResourceEconomy/Inventory/Construction remain untouched until an explicit bridge PR is introduced.

## Runtime

State root: `Workspace.AstraSurvivalCraftingState`

Core reads current P7/W7 state through a read-only adapter and writes diagnostics only beneath its own state root.

## Composition

S1-S12 are intended to stack only on S0 and remain mutually optional. A later composition PR can install adapters between S-series data/contracts and W6/P7/legacy systems.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S0Status == "PASS"`.

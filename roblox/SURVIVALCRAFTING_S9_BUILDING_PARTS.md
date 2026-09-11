# SurvivalCrafting S9 — Building Parts

Data-only snap/tier/health/upkeep/upgrade contracts for modular base pieces such as foundations, walls, door frames and roofs.

S9 does not place Roblox Parts, consume materials, mutate legacy Construction or resolve structure damage. A later placement adapter can use W5 affordance checks plus S9 snap rules before committing a real build transaction.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S9BuildingParts.S9Status == "PASS"`.

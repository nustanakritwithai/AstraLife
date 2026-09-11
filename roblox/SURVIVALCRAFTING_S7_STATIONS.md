# SurvivalCrafting S7 — Processing Stations

Data-only capability contracts for Campfire, Furnace, Workbench and Anvil. Defines station tier, input/fuel/output/queue slots, speed multiplier and supported processing capabilities.

S7 does not spawn station Instances, consume fuel or execute recipes. A later composition layer may bind real Structures to these station profiles.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S7Stations.S7Status == "PASS"`.

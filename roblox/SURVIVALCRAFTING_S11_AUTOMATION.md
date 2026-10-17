# SurvivalCrafting S11 — Automated Resource Stations

Quote-only production contracts for Quarry, Sawmill and SalvageRecycler. Quotes include cycle duration, fuel requirement, output capacity requirement and requested outputs.

S11 never withdraws Living World resources, consumes fuel or deposits outputs. W6/W7 plus later container/inventory adapters must commit every resource transaction.

API: `ServerScriptService/AstraSurvivalCrafting/S11AutomationApi`.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S11Automation.S11Status == "PASS"`.

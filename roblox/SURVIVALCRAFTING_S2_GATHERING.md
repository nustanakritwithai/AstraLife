# SurvivalCrafting S2 — Gathering Contracts

Data-only rules that map resource-source kinds to required tool class/tier, hardness and expected item yields.

S2 never withdraws Living World resources and never edits legacy ResourceEconomy or Inventory. W6/W7 remain authoritative for physical resource quantities and committed world transactions.

A later bridge may pass W6/W7 source observations plus a tool descriptor into S2, then ask the authoritative transaction service to commit the actual harvest.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S2Gathering.S2Status == "PASS"`.

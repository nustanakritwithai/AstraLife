# SurvivalCrafting S12 — Durability / Repair / Decay

Quote-only policy engine for tool/item wear, repair material requirements, structure decay under exposure/upkeep and aggregate base upkeep requirements.

S12 does not mutate item durability, structure health or inventories. Real spend/repair/damage must be committed through the authoritative item/structure/inventory adapters during composition.

API: `ServerScriptService/AstraSurvivalCrafting/S12DurabilityApi`.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S12Durability.S12Status == "PASS"`.

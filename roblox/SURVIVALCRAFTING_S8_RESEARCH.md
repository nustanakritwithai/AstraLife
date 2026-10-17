# SurvivalCrafting S8 — Research / Blueprints

Two-phase research unlock registry with prerequisite graph, Scrap cost quotes, idempotent commits and external payment-receipt gating.

S8 never removes Scrap itself. An inventory/treasury adapter must commit payment first and supply a receipt. Persistence is intentionally left to a later save adapter.

API: `ServerScriptService/AstraSurvivalCrafting/S8ResearchApi`.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S8Research.S8Status == "PASS"`.

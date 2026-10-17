# SurvivalCrafting S4 — Inventory V2

Standalone item-stack container library with slot capacity, stack limits, durability/quality/metadata fields, split support and bounded idempotent transaction history.

S4 does not replace or mutate the P1-P7 legacy `Inventory.lua`. A later bridge can migrate or mirror selected Agent containers after integration tests.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S4InventoryV2.S4Status == "PASS"`.

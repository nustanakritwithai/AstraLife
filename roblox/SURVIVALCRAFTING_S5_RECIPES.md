# SurvivalCrafting S5 — Recipe Graph

Data-driven production graph for raw -> processed -> component -> tool/station/build-part progression.

Every recipe declares inputs, outputs, required station, craft duration in ticks and research tier. S5 does not spend inventory or execute crafting; those responsibilities belong to later queue/adapter layers.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S5Recipes.S5Status == "PASS"`.

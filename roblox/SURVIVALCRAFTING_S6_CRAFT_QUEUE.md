# SurvivalCrafting S6 — Craft Queue

Server-owned bounded craft-job lifecycle: queued -> running -> completed_pending_commit -> committed/commit_failed, with cancellation and idempotent enqueue transaction IDs.

S6 deliberately does not spend inputs or create outputs. A later composition adapter must reserve/spend from S4 or another authoritative inventory and call Commit only after inventory/resource transaction success.

API: `ServerScriptService/AstraSurvivalCrafting/S6CraftQueueApi`.

Acceptance target: `Workspace.AstraSurvivalCraftingState.S6CraftQueue.S6Status == "PASS"`.

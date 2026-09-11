# K10 Treasury & Ledger

Server-only transactional treasury for Kingdom modules.

API lives under `ServerScriptService/AstraKingdom/K10TreasuryApi` as BindableFunctions:
- Credit
- Debit
- Reserve
- Release
- CommitReserve
- GetSnapshot

Properties:
- idempotent transaction IDs
- reservation before spending
- bounded history
- balance/reserved/available invariants
- no Colony stock mutation
- state projection under `Workspace.AstraKingdomState/K10Treasury`

K10 is intentionally independent of K11+; later modules may consume this API after integration.

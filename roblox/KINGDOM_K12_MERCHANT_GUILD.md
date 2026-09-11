# K12 Merchant Guild / Warehouse

Server-owned registry for merchant guild metadata without taking authority over Agents, stock, routes or WorldSim.

API: `ServerScriptService/AstraKingdom/K12MerchantGuildApi`
- EnsureGuild
- RegisterWarehouse
- SetMember
- RecordTrade
- GetSnapshot

Membership is a Kingdom registry reference only; it never writes Agent attributes. Warehouses are capacity records only; they never move or duplicate stock. Trade outcomes are idempotent per transaction id and feed guild reputation/statistics.

Runtime state is published under `Workspace.AstraKingdomState/K12MerchantGuild`.

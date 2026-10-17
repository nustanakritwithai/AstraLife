local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local Catalog = require(SurvivalCrafting.S8.ResearchCatalog)
local Registry = require(SurvivalCrafting.S8.ResearchRegistry)
local S8Verifier = require(SurvivalCrafting.S8.S8Verifier)

local scope = StateWriter.Scope("S8Research")
local registry = Registry.new(Catalog)
local api = Instance.new("BindableFunction")
api.Name = "S8ResearchApi"
api.Parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService

api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "Quote" then return registry:Quote(payload.profileId or "default", payload.nodeId) end
    if action == "Commit" then return registry:Commit(payload.profileId or "default", payload.nodeId, payload.transactionId, payload.paymentReceipt) end
    if action == "Snapshot" then return registry:Snapshot(payload.profileId or "default") end
    return nil, "unknown_action"
end

scope:SetAttribute("Version", "S8-1")
scope:SetAttribute("OwnsScrapCurrency", false)
scope:SetAttribute("RequiresPaymentReceipt", true)
scope:SetAttribute("PersistenceMode", "external-adapter-required")
S8Verifier.Verify(Catalog, Registry, scope)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local Catalog = require(SurvivalCrafting.S11.AutomatedStationCatalog)
local Verifier = require(SurvivalCrafting.S11.S11Verifier)

local scope = StateWriter.Scope("S11Automation")
local api = Instance.new("BindableFunction")
api.Name = "S11AutomationApi"
api.Parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService
api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "QuoteCycle" then return Catalog.QuoteCycle(payload.stationId, payload.context or {}) end
    if action == "Profiles" then return Catalog.All() end
    return nil, "unknown_action"
end
scope:SetAttribute("Version", "S11-1")
scope:SetAttribute("OwnsWorldResources", false)
scope:SetAttribute("OwnsFuelTransactions", false)
scope:SetAttribute("OwnsOutputCommit", false)
scope:SetAttribute("RequiresAuthoritativeCommit", true)
Verifier.Verify(Catalog, scope)

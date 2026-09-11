local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local Policy = require(SurvivalCrafting.S12.DurabilityPolicy)
local Verifier = require(SurvivalCrafting.S12.S12Verifier)

local scope = StateWriter.Scope("S12Durability")
local api = Instance.new("BindableFunction")
api.Name = "S12DurabilityApi"
api.Parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService
api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "Wear" then return Policy.Wear(payload.current, payload.maxValue, payload.workUnits, payload.wearRate) end
    if action == "RepairQuote" then return Policy.RepairQuote(payload.current, payload.maxValue, payload.materials, payload.targetFraction) end
    if action == "DecayQuote" then return Policy.StructureDecayQuote(payload.maxHealth, payload.tier, payload.exposure, payload.upkeepCovered, payload.elapsedTicks) end
    if action == "UpkeepQuote" then return Policy.UpkeepQuote(payload.parts, payload.intervalTicks) end
    return nil, "unknown_action"
end
scope:SetAttribute("Version", "S12-1")
scope:SetAttribute("OwnsDurabilityMutation", false)
scope:SetAttribute("OwnsStructureHealth", false)
scope:SetAttribute("OwnsMaterialSpend", false)
scope:SetAttribute("PolicyMode", "quote-only")
Verifier.Verify(Policy, scope)

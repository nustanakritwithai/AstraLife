local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SurvivalCrafting = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("SurvivalCrafting")
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local WorldItemAdapter = require(SurvivalCrafting.Adapter.WorldItemAdapter)
local InventoryShadow = require(SurvivalCrafting.Adapter.InventoryShadow)
local I3Verifier = require(SurvivalCrafting.Adapter.I3Verifier)

-- I3 composition: W6 committed harvest → WorldGatherReceipt → Convert → S4 →
-- legacy Carry projection. This service owns the I3 scope + Bindable API; it
-- never withdraws Living World resources itself.
local scope = StateWriter.Scope("I3InventoryShadow")
scope:SetAttribute("Version", "I3-1")
scope:SetAttribute("OwnsWorldResources", false)
scope:SetAttribute("OwnsLegacyInventory", false)
scope:SetAttribute("ShadowPhase", "A")

local parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService
local existing = parent:FindFirstChild("I3InventoryShadowApi")
if existing then existing:Destroy() end

local api = Instance.new("BindableFunction")
api.Name = "I3InventoryShadowApi"
api.Parent = parent
api.OnInvoke = function(action, payload)
	payload = payload or {}
	if action == "ApplyCommittedHarvest" then
		return InventoryShadow.ApplyCommittedHarvest(payload)
	end
	if action == "RemoveLegacyProjection" then
		return InventoryShadow.RemoveLegacyProjection(
			payload.actorId,
			payload.resourceType,
			payload.amount,
			payload.transactionId,
			payload.options
		)
	end
	if action == "EnsureLegacyProjection" then
		return InventoryShadow.EnsureLegacyProjection(payload.actorId, payload.legacyInventory)
	end
	if action == "GetProjection" then
		return InventoryShadow.GetProjection(payload.actorId)
	end
	if action == "ProjectedAmount" then
		return InventoryShadow.ProjectedAmount(payload.actorId, payload.resourceType)
	end
	if action == "Count" then
		return InventoryShadow.Count(payload.actorId, payload.itemId)
	end
	if action == "LegacyNeverExceedsProjection" then
		return InventoryShadow.LegacyNeverExceedsProjection(payload.actorId, payload.legacyInventory)
	end
	return nil, "unknown_action"
end

I3Verifier.Verify(InventoryShadow, WorldItemAdapter, scope)

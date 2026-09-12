local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local InventoryV2 = require(SurvivalCrafting.S4.InventoryV2)
local InventoryRegistry = require(SurvivalCrafting.S4.InventoryRegistry)
local ItemCatalog = require(SurvivalCrafting.S1.ItemCatalog)
local S4Verifier = require(SurvivalCrafting.S4.S4Verifier)

local scope = StateWriter.Scope("S4InventoryV2")
scope:SetAttribute("Version", "S4-1")
scope:SetAttribute("OwnsLegacyInventory", false)
scope:SetAttribute("InventoryMode", "runtime-actor-registry")
scope:SetAttribute("SupportsMetadata", true)
scope:SetAttribute("SupportsDurability", true)
scope:SetAttribute("SupportsIdempotentTransactions", true)

-- Real S4 Add/Remove API (per-actor InventoryV2). Self-test verifier still runs
-- against a fresh local instance and does not mutate the runtime registry.
local parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService
local existing = parent:FindFirstChild("S4InventoryV2Api")
if existing then existing:Destroy() end

local api = Instance.new("BindableFunction")
api.Name = "S4InventoryV2Api"
api.Parent = parent
api.OnInvoke = function(action, payload)
	payload = payload or {}
	if action == "GetOrCreate" then
		local inv = InventoryRegistry.Get(payload.actorId, payload.slotCapacity)
		return { ok = true, actorId = payload.actorId, snapshot = inv:Snapshot() }
	end
	if action == "Add" then
		local inv = InventoryRegistry.Get(payload.actorId, payload.slotCapacity)
		local spec = payload.spec or {}
		if spec.maxStack == nil and type(spec.itemId) == "string" then
			local item = ItemCatalog.Get(spec.itemId)
			if item then
				local copy = {}
				for key, value in pairs(spec) do copy[key] = value end
				copy.maxStack = item.maxStack
				spec = copy
			end
		end
		return inv:Add(spec, payload.transactionId)
	end
	if action == "Remove" then
		local inv = InventoryRegistry.Get(payload.actorId)
		return inv:Remove(payload.itemId, payload.quantity, payload.transactionId)
	end
	if action == "Count" then
		return InventoryRegistry.Get(payload.actorId):Count(payload.itemId)
	end
	if action == "Snapshot" then
		return InventoryRegistry.Get(payload.actorId):Snapshot()
	end
	if action == "Has" then
		return InventoryRegistry.Has(payload.actorId)
	end
	return nil, "unknown_action"
end

scope:SetAttribute("S4ApiExposed", true)
S4Verifier.Verify(InventoryV2, scope)

local InventoryV2 = require(script.Parent.InventoryV2)

-- Shared per-actor InventoryV2 instances for S4 runtime API + I3 shadow migration.
local InventoryRegistry = {}

local actors = {}
local DEFAULT_SLOTS = 24

function InventoryRegistry.Get(actorId, slotCapacity)
	assert(type(actorId) == "string" and actorId ~= "", "actorId required")
	local entry = actors[actorId]
	if not entry then
		entry = InventoryV2.new(slotCapacity or DEFAULT_SLOTS)
		actors[actorId] = entry
	end
	return entry
end

function InventoryRegistry.Has(actorId)
	return actors[actorId] ~= nil
end

function InventoryRegistry.Reset(actorId)
	if actorId then
		actors[actorId] = nil
	else
		actors = {}
	end
end

function InventoryRegistry._actorsForTest()
	return actors
end

return InventoryRegistry

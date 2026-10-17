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

-- Delete only actors whose id starts with prefix (e.g. "i6-"). Never wipe the live registry.
function InventoryRegistry.ResetMatching(prefix)
	assert(type(prefix) == "string" and prefix ~= "", "prefix required")
	local removed = 0
	local toDelete = {}
	for actorId in pairs(actors) do
		if string.sub(actorId, 1, #prefix) == prefix then
			table.insert(toDelete, actorId)
		end
	end
	for _, actorId in ipairs(toDelete) do
		actors[actorId] = nil
		removed += 1
	end
	return removed
end

function InventoryRegistry._actorsForTest()
	return actors
end

return InventoryRegistry

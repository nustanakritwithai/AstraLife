local WorldItemAdapter = require(script.Parent.WorldItemAdapter)
local GatheringContracts = require(script.Parent.Parent.S2.GatheringContracts)
local ItemCatalog = require(script.Parent.Parent.S1.ItemCatalog)
local InventoryRegistry = require(script.Parent.Parent.S4.InventoryRegistry)

-- I3 Phase A: W6 committed WorldGatherReceipt → S4 InventoryV2 (canonical candidate)
-- → legacy Carry_* projection. S4 holds Convert item yields; projection tracks the
-- LivingWorld world-resource units mirrored for P1–P7.5 Carry compatibility.
-- Legacy physical collect remains distinguishable (no S4 write / no projection bump).
local InventoryShadow = {}
InventoryShadow.ProvenanceLivingWorld = WorldItemAdapter.Provenance
InventoryShadow.ProvenanceLegacy = "Legacy"

local actors = {}
local DEFAULT_WORLD_UNITS = {
	Wood = 1,
	Food = 1,
	Stone = 1,
	Water = 0.05,
}

local DEFAULT_TOOL = {
	Wood = { class = "axe", tier = 0 },
	Food = { class = "hand", tier = 0 },
	Stone = { class = "pickaxe", tier = 0 },
	Water = { class = "hand", tier = 0 },
}

local function actorState(actorId)
	local state = actors[actorId]
	if not state then
		state = {
			projection = {},
			receipts = {},
			receiptOrder = {},
			removeSeen = {},
			removeOrder = {},
			maxHistory = 256,
		}
		actors[actorId] = state
	end
	return state
end

local function rememberReceipt(state, transactionId, record)
	if state.receipts[transactionId] == nil then
		table.insert(state.receiptOrder, transactionId)
	end
	state.receipts[transactionId] = record
	while #state.receiptOrder > state.maxHistory do
		local old = table.remove(state.receiptOrder, 1)
		state.receipts[old] = nil
	end
end

local function rememberRemove(state, transactionId, record)
	if state.removeSeen[transactionId] == nil then
		table.insert(state.removeOrder, transactionId)
	end
	state.removeSeen[transactionId] = record
	while #state.removeOrder > state.maxHistory do
		local old = table.remove(state.removeOrder, 1)
		state.removeSeen[old] = nil
	end
end

local function cloneTable(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = cloneTable(v) end
	return out
end

local function defaultContext(worldResourceType, context)
	context = type(context) == "table" and context or {}
	if worldResourceType == "Food" and context.source == nil then
		-- W6 HarvestToInventory uses the Forage affordance for Food.
		return { source = "forage" }
	end
	return context
end

local function defaultTool(worldResourceType, toolClass, toolTier)
	local fallback = DEFAULT_TOOL[worldResourceType] or { class = "hand", tier = 0 }
	return {
		class = (type(toolClass) == "string" and toolClass ~= "" and toolClass) or fallback.class,
		tier = type(toolTier) == "number" and toolTier or fallback.tier,
		efficiency = 1,
	}
end

local function yieldsForFraction(sourceKind, tool, fraction)
	local full, reason = GatheringContracts.EstimateYield(sourceKind, tool, 1)
	if not full then return nil, reason end
	local yields = {}
	for itemId, amount in pairs(full) do
		yields[itemId] = math.floor(amount * fraction + 1e-9)
	end
	return yields
end

function InventoryShadow.GetProjection(actorId)
	local state = actors[actorId]
	if not state then return {} end
	return cloneTable(state.projection)
end

function InventoryShadow.ProjectedAmount(actorId, resourceType)
	local state = actors[actorId]
	if not state then return 0 end
	return state.projection[resourceType] or 0
end

function InventoryShadow.GetInventory(actorId)
	return InventoryRegistry.Get(actorId)
end

function InventoryShadow.Count(actorId, itemId)
	return InventoryRegistry.Get(actorId):Count(itemId)
end

-- Apply a committed W6 harvest as WorldGatherReceipt → Convert → S4 Add.
-- Idempotent on transactionId: retries return the remembered result without duplicating.
function InventoryShadow.ApplyCommittedHarvest(input)
	if type(input) ~= "table" then return nil, "invalid_input" end
	local actorId = input.actorId
	local transactionId = input.transactionId
	if type(actorId) ~= "string" or actorId == "" then return nil, "invalid_actorId" end
	if type(transactionId) ~= "string" or transactionId == "" then return nil, "invalid_transactionId" end

	local state = actorState(actorId)
	local previous = state.receipts[transactionId]
	if previous then
		local copy = cloneTable(previous)
		copy.duplicate = true
		return copy
	end

	local worldResourceType = input.worldResourceType
	local context = defaultContext(worldResourceType, input.context)
	local sourceKind = input.sourceKind
	local resolveReason = nil
	if type(sourceKind) ~= "string" or sourceKind == "" then
		sourceKind, resolveReason = WorldItemAdapter.ResolveSourceKind(worldResourceType, context)
	end
	if not sourceKind then return nil, resolveReason or "unmapped_resource" end

	local tool = defaultTool(worldResourceType, input.toolClass, input.toolTier)
	local worldUnitsPerAction = input.worldUnitsPerAction or DEFAULT_WORLD_UNITS[worldResourceType] or 1

	local receipt, buildReason = WorldItemAdapter.BuildReceipt({
		transactionId = transactionId,
		actorId = actorId,
		worldTick = input.worldTick or 0,
		cellKey = input.cellKey or "unknown",
		worldResourceType = worldResourceType,
		sourceKind = sourceKind,
		actualWithdrawn = input.actualWithdrawn,
		toolClass = tool.class,
		toolTier = tool.tier,
	})
	if not receipt then return nil, buildReason end

	local yields, enriched = WorldItemAdapter.Convert(receipt, {
		tool = tool,
		worldUnitsPerAction = worldUnitsPerAction,
	})
	if not yields then return nil, enriched end

	local inv = InventoryRegistry.Get(actorId)
	local accepted = {}
	local rejected = {}
	for itemId, amount in pairs(yields) do
		if amount > 0 then
			local catalog = ItemCatalog.Get(itemId)
			local result = inv:Add({
				itemId = itemId,
				quantity = amount,
				maxStack = catalog and catalog.maxStack or 50,
				metadata = {
					provenance = InventoryShadow.ProvenanceLivingWorld,
					worldResourceType = worldResourceType,
					sourceKind = sourceKind,
					receiptId = transactionId,
				},
			}, transactionId .. ":add:" .. itemId)
			accepted[itemId] = result.accepted
			if result.rejected > 0 then rejected[itemId] = result.rejected end
		else
			accepted[itemId] = 0
		end
	end

	local projected = math.max(0, receipt.actualWithdrawn)
	state.projection[worldResourceType] = (state.projection[worldResourceType] or 0) + projected

	local record = {
		ok = true,
		duplicate = false,
		transactionId = transactionId,
		actorId = actorId,
		receipt = receipt,
		yields = yields,
		accepted = accepted,
		rejected = rejected,
		projectedResourceType = worldResourceType,
		projectedAmount = projected,
		projection = cloneTable(state.projection),
		provenance = InventoryShadow.ProvenanceLivingWorld,
	}
	rememberReceipt(state, transactionId, record)
	return cloneTable(record)
end

-- Remove S4 items corresponding to legacy world-resource units leaving carry
-- (deposit / build delivery). Idempotent on transactionId.
function InventoryShadow.RemoveLegacyProjection(actorId, resourceType, amount, transactionId, options)
	if type(actorId) ~= "string" or actorId == "" then return nil, "invalid_actorId" end
	if type(resourceType) ~= "string" or resourceType == "" then return nil, "invalid_resourceType" end
	transactionId = tostring(transactionId or "")
	if transactionId == "" then return nil, "invalid_transactionId" end

	local state = actorState(actorId)
	local previous = state.removeSeen[transactionId]
	if previous then
		local copy = cloneTable(previous)
		copy.duplicate = true
		return copy
	end

	amount = math.max(0, tonumber(amount) or 0)
	options = options or {}
	local context = defaultContext(resourceType, options.context)
	local sourceKind = options.sourceKind
	if type(sourceKind) ~= "string" or sourceKind == "" then
		sourceKind = select(1, WorldItemAdapter.ResolveSourceKind(resourceType, context))
	end
	if not sourceKind then
		local record = {
			ok = false,
			duplicate = false,
			transactionId = transactionId,
			reason = "unmapped_resource",
			removedItems = {},
			projectedRemoved = 0,
		}
		rememberRemove(state, transactionId, record)
		return cloneTable(record)
	end

	local tool = defaultTool(resourceType, options.toolClass, options.toolTier)
	local worldUnitsPerAction = options.worldUnitsPerAction or DEFAULT_WORLD_UNITS[resourceType] or 1
	local fraction = worldUnitsPerAction > 0 and (amount / worldUnitsPerAction) or 0
	local yields, yieldReason = yieldsForFraction(sourceKind, tool, fraction)
	if not yields then
		local record = {
			ok = false,
			duplicate = false,
			transactionId = transactionId,
			reason = yieldReason,
			removedItems = {},
			projectedRemoved = 0,
		}
		rememberRemove(state, transactionId, record)
		return cloneTable(record)
	end

	local inv = InventoryRegistry.Get(actorId)
	local removedItems = {}
	local missingItems = {}
	for itemId, qty in pairs(yields) do
		if qty > 0 then
			local result = inv:Remove(itemId, qty, transactionId .. ":rm:" .. itemId)
			removedItems[itemId] = result.removed
			if result.missing > 0 then missingItems[itemId] = result.missing end
		end
	end

	local available = state.projection[resourceType] or 0
	local projectedRemoved = math.min(available, amount)
	state.projection[resourceType] = available - projectedRemoved

	local record = {
		ok = true,
		duplicate = false,
		transactionId = transactionId,
		resourceType = resourceType,
		requested = amount,
		removedItems = removedItems,
		missingItems = missingItems,
		projectedRemoved = projectedRemoved,
		projection = cloneTable(state.projection),
	}
	rememberRemove(state, transactionId, record)
	return cloneTable(record)
end

-- Ensure legacy Inventory carries at least the LivingWorld projection for each
-- mirrored resource type (projection adapter write). Does not strip legacy-only
-- extras so mixed provenance remains representable in total Carry_*.
function InventoryShadow.EnsureLegacyProjection(actorId, legacyInventory)
	if type(actorId) ~= "string" or not legacyInventory then return nil, "invalid_args" end
	local state = actorState(actorId)
	local applied = {}
	for resourceType, cap in pairs(state.projection) do
		local current = legacyInventory:Get(resourceType)
		if current < cap then
			legacyInventory:Add(resourceType, cap - current)
		end
		applied[resourceType] = legacyInventory:Get(resourceType)
	end
	return { ok = true, projection = cloneTable(state.projection), legacy = applied }
end

-- LivingWorld-backed carry must not exceed the S4 shadow projection. Returns
-- false when any projected resource in legacyInventory is above its cap.
-- Legacy-only resources (no projection entry) are ignored.
function InventoryShadow.LegacyNeverExceedsProjection(actorId, legacyInventory)
	local state = actors[actorId]
	if not state or not legacyInventory then return true end
	for resourceType, cap in pairs(state.projection) do
		-- Compare the LivingWorld projection cap against how much of that
		-- resource the caller attributes to LivingWorld. When the full
		-- inventory is LivingWorld-only (verifier), Get() is the right signal.
		if (legacyInventory:Get(resourceType) or 0) > cap + 1e-9 then
			return false, resourceType
		end
	end
	return true
end

function InventoryShadow.Reset(actorId)
	if actorId then
		actors[actorId] = nil
		InventoryRegistry.Reset(actorId)
	else
		actors = {}
		InventoryRegistry.Reset()
	end
end

return InventoryShadow

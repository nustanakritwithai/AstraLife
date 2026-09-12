-- I6 profession adapter: maps P6 Role → allowed S/B actions without owning Role/Skill/Goal.
-- Gatherer consults S2/S3 quotes for W6 harvest context; Builder prefers I5 B1 + S4 materials.
-- Never withdraws Living World resources; never writes Role/Skill/Goal.

local WorldItemAdapter = require(script.Parent.WorldItemAdapter)
local GatheringContracts = require(script.Parent.Parent.S2.GatheringContracts)
local ToolCatalog = require(script.Parent.Parent.S3.ToolCatalog)
local InventoryRegistry = require(script.Parent.Parent.S4.InventoryRegistry)
local ItemCatalog = require(script.Parent.Parent.S1.ItemCatalog)
local CraftedBuildPartMapping = require(script.Parent.Parent.Parent.Building.CraftedBuildPartMapping)

local ProfessionAdapter = {}
ProfessionAdapter.Version = "I6-1"
ProfessionAdapter.ProfessionMode = "adapter"

local ROLE_ACTIONS = {
	Gatherer = {
		HarvestQuote = true,
		W6Harvest = true,
		Deposit = true,
		Deliver = true,
	},
	Builder = {
		CraftQuote = true,
		CraftStart = true,
		B1Place = true,
		B1Repair = true,
		B1Upgrade = true,
		B1Demolish = true,
		B1Preview = true,
	},
	Scout = {
		Explore = true,
		Communicate = true,
	},
}

-- Legacy colony resource types used by B1 MaterialGradeCatalog recipes → S1 item ids.
local COLONY_TO_S1 = {
	Wood = "Log",
	Stone = "StoneChunk",
	Metal = "MetalFragment",
}

local RESOURCE_CONTEXT = {
	Wood = {},
	Food = { source = "forage" },
	Water = {},
	Stone = {},
}

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = clone(v)
	end
	return out
end

function ProfessionAdapter.AllowedActions(role)
	local map = ROLE_ACTIONS[role]
	if not map then
		return {}
	end
	local list = {}
	for action in pairs(map) do
		table.insert(list, action)
	end
	table.sort(list)
	return list
end

function ProfessionAdapter.IsActionAllowed(role, action)
	local map = ROLE_ACTIONS[role]
	return map ~= nil and map[action] == true
end

-- Explicit non-authority: never assign/mutate Role/Skill/Goal.
function ProfessionAdapter.WritesRoleSkillGoal()
	return false
end

function ProfessionAdapter.WithdrawsWorldResources()
	return false
end

local function resolveSourceKind(worldResourceType, context)
	context = context or RESOURCE_CONTEXT[worldResourceType] or {}
	local sourceKind, reason = WorldItemAdapter.ResolveSourceKind(worldResourceType, context)
	return sourceKind, reason, context
end

local function handTool()
	return ToolCatalog.Describe("Hand") or { id = "Hand", class = "hand", tier = 0, efficiency = 0.35 }
end

local function bestToolForContract(actorId, contract)
	local preferredClass = contract and contract.toolClass or "hand"
	local minTier = contract and contract.minTier or 0
	local best = nil

	if preferredClass == "hand" then
		best = handTool()
	end

	local inv = InventoryRegistry.Get(actorId)
	local snap = inv:Snapshot()
	for _, stack in ipairs(snap.slots or {}) do
		local desc = ToolCatalog.Describe(stack.itemId, stack.metadata and stack.metadata.durability)
		if desc
			and desc.class == preferredClass
			and (desc.tier or 0) >= minTier
			and (stack.quantity or 0) > 0
		then
			if not best
				or (desc.tier or 0) > (best.tier or 0)
				or ((desc.tier or 0) == (best.tier or 0) and (desc.efficiency or 0) > (best.efficiency or 0))
			then
				best = desc
			end
		end
	end

	if not best and preferredClass ~= "hand" and minTier <= 0 then
		-- Tier-0 axe/pick contracts still allow forage-style fallbacks only when minTier is 0
		-- and GatheringContracts.CanGather accepts hand for hand-class sources. For axe/pick
		-- with minTier 0, default Hand fails CanGather — return a virtual matching class at
		-- tier 0 so quotes remain valid without inventing inventory tools (W6 still harvests).
		best = {
			id = "Virtual:" .. preferredClass,
			class = preferredClass,
			tier = 0,
			efficiency = 1,
			virtual = true,
		}
	elseif not best then
		best = handTool()
	end

	return best
end

-- S2/S3 quote only — never withdraws world stock.
function ProfessionAdapter.QuoteGather(worldResourceType, actorId, opts)
	opts = opts or {}
	local context = opts.context or RESOURCE_CONTEXT[worldResourceType] or {}
	local sourceKind, resolveReason = resolveSourceKind(worldResourceType, context)
	if not sourceKind then
		return nil, resolveReason or "unmapped_resource"
	end

	local contract = GatheringContracts.Get(sourceKind)
	if not contract then
		return nil, "unknown_source"
	end

	local tool = bestToolForContract(actorId or "anonymous", contract)
	local canGather, reason = GatheringContracts.CanGather(sourceKind, tool)
	local yields = nil
	if canGather then
		yields = GatheringContracts.EstimateYield(sourceKind, tool, opts.remainingFraction or 1)
	end

	return {
		ok = canGather == true,
		reason = reason,
		worldResourceType = worldResourceType,
		sourceKind = sourceKind,
		context = clone(context),
		toolClass = tool.class,
		toolTier = tool.tier or 0,
		toolId = tool.id,
		toolVirtual = tool.virtual == true,
		efficiency = tool.efficiency,
		yields = yields,
		contractToolClass = contract.toolClass,
		contractMinTier = contract.minTier,
		withdrewWorld = false,
	}
end

-- Context bag for SurvivalBridge HarvestToInventory (I3 Convert path).
function ProfessionAdapter.HarvestContext(worldResourceType, actorId, opts)
	local quote, err = ProfessionAdapter.QuoteGather(worldResourceType, actorId, opts)
	if not quote then
		-- Still allow forage/wood with defaults when quote fails (e.g. no actor yet).
		local context = (opts and opts.context) or RESOURCE_CONTEXT[worldResourceType] or {}
		local sourceKind = select(1, resolveSourceKind(worldResourceType, context))
		local fallbackClass = worldResourceType == "Wood" and "axe"
			or worldResourceType == "Stone" and "pickaxe"
			or "hand"
		return {
			ok = sourceKind ~= nil,
			sourceKind = sourceKind,
			context = context,
			toolClass = fallbackClass,
			toolTier = 0,
			fallback = true,
			error = err,
			withdrewWorld = false,
		}
	end
	return {
		ok = quote.ok,
		sourceKind = quote.sourceKind,
		context = quote.context,
		toolClass = quote.toolClass,
		toolTier = quote.toolTier,
		toolId = quote.toolId,
		yields = quote.yields,
		reason = quote.reason,
		withdrewWorld = false,
	}
end

function ProfessionAdapter.ListPlaceableBuildParts(actorId)
	local inv = InventoryRegistry.Get(actorId)
	local snap = inv:Snapshot()
	local found = {}
	for _, stack in ipairs(snap.slots or {}) do
		local mapping = CraftedBuildPartMapping.Get(stack.itemId)
		if mapping and (stack.quantity or 0) > 0 then
			table.insert(found, {
				itemId = stack.itemId,
				quantity = stack.quantity,
				pieceType = mapping.pieceType,
				materialGrade = mapping.materialGrade,
			})
		end
	end
	table.sort(found, function(a, b)
		if a.itemId == b.itemId then
			return false
		end
		return a.itemId < b.itemId
	end)
	return found
end

function ProfessionAdapter.PickPlaceableBuildPart(actorId)
	local list = ProfessionAdapter.ListPlaceableBuildParts(actorId)
	return list[1]
end

-- S4-backed economy for B1 Repair/Upgrade/Demolish recipes keyed by Wood/Stone/Metal.
function ProfessionAdapter.MakeS4Economy(actorId)
	local inv = InventoryRegistry.Get(actorId)
	return {
		CanAfford = function(_, recipe)
			for resourceType, amount in pairs(recipe or {}) do
				local itemId = COLONY_TO_S1[resourceType] or resourceType
				local need = math.ceil(math.max(0, tonumber(amount) or 0))
				if inv:Count(itemId) < need then
					return false
				end
			end
			return true
		end,
		Spend = function(_, recipe)
			for resourceType, amount in pairs(recipe or {}) do
				local itemId = COLONY_TO_S1[resourceType] or resourceType
				local need = math.ceil(math.max(0, tonumber(amount) or 0))
				if need > 0 then
					local result = inv:Remove(itemId, need, "i6:economy:" .. actorId .. ":" .. itemId .. ":" .. tostring(need))
					if not result or (result.removed or 0) < need then
						return false
					end
				end
			end
			return true
		end,
		CanDeposit = function()
			return true
		end,
		Deposit = function(_, recipe)
			for resourceType, amount in pairs(recipe or {}) do
				local itemId = COLONY_TO_S1[resourceType] or resourceType
				local qty = math.floor(math.max(0, tonumber(amount) or 0))
				if qty > 0 then
					local catalog = ItemCatalog.Get(itemId)
					inv:Add({
						itemId = itemId,
						quantity = qty,
						maxStack = catalog and catalog.maxStack or 50,
						metadata = { provenance = "B1Refund" },
					}, "i6:refund:" .. actorId .. ":" .. itemId)
				end
			end
			return true
		end,
	}
end

-- Consume one crafted build part from S4 and place via B1 PlaceRoot (W5 gated inside).
function ProfessionAdapter.PlaceCraftedPart(BuildingLifecycleService, spec)
	if type(spec) ~= "table" then
		return nil, "invalid_spec"
	end
	local actorId = spec.actorId
	local itemId = spec.itemId
	local transactionId = spec.transactionId
	if type(actorId) ~= "string" or actorId == "" then
		return nil, "invalid_actorId"
	end
	if type(itemId) ~= "string" or itemId == "" then
		return nil, "invalid_itemId"
	end
	if type(transactionId) ~= "string" or transactionId == "" then
		return nil, "invalid_transactionId"
	end
	if not BuildingLifecycleService or not BuildingLifecycleService.PlaceRoot then
		return nil, "lifecycle_unavailable"
	end

	local mapping = CraftedBuildPartMapping.Get(itemId)
	if not mapping then
		return nil, "unmapped_build_part"
	end

	local position = spec.position
	if typeof(position) ~= "Vector3" then
		return nil, "invalid_position"
	end

	local yaw = spec.yawDegrees or 0
	local preview = BuildingLifecycleService.PreviewRoot(mapping.pieceType, position, yaw)
	if not preview or preview.allowed ~= true then
		return nil, (preview and preview.reason) or "placement_rejected"
	end

	local inv = InventoryRegistry.Get(actorId)
	if inv:Count(itemId) < 1 then
		return nil, "missing_build_part"
	end

	local removed = inv:Remove(itemId, 1, transactionId .. ":consume")
	-- InventoryV2 remembers by transactionId; retries return the prior removed count.
	if not removed or (removed.removed or 0) < 1 then
		return nil, "consume_failed"
	end

	local piece, reason = BuildingLifecycleService.PlaceRoot(mapping.pieceType, position, yaw, {
		materialGrade = mapping.materialGrade,
		actorId = actorId,
		itemId = itemId,
		transactionId = transactionId,
		source = "I6ProfessionAdapter",
	})
	if not piece then
		-- Best-effort refund on place failure (new tx suffix to avoid clobbering consume dedupe).
		local catalog = ItemCatalog.Get(itemId)
		inv:Add({
			itemId = itemId,
			quantity = 1,
			maxStack = catalog and catalog.maxStack or 50,
			metadata = { provenance = "I6PlaceRefund" },
		}, transactionId .. ":refund")
		return nil, reason or "place_failed"
	end

	return {
		ok = true,
		pieceId = piece.id,
		pieceType = piece.pieceType,
		materialGrade = mapping.materialGrade,
		itemId = itemId,
		transactionId = transactionId,
		actorId = actorId,
		eventName = "BuildingPlaced",
		authority = "B1",
	}
end

function ProfessionAdapter.RepairPiece(BuildingLifecycleService, spec)
	if type(spec) ~= "table" then
		return nil, "invalid_spec"
	end
	local actorId = spec.actorId
	local pieceId = spec.pieceId
	local transactionId = spec.transactionId
	if type(actorId) ~= "string" or actorId == "" then
		return nil, "invalid_actorId"
	end
	if type(pieceId) ~= "string" or pieceId == "" then
		return nil, "invalid_pieceId"
	end
	if type(transactionId) ~= "string" or transactionId == "" then
		return nil, "invalid_transactionId"
	end
	if not BuildingLifecycleService or not BuildingLifecycleService.Repair then
		return nil, "lifecycle_unavailable"
	end

	local economy = ProfessionAdapter.MakeS4Economy(actorId)
	local repaired = BuildingLifecycleService.Repair(pieceId, economy, spec.requestedHealth, transactionId)
	if not repaired or not repaired.ok then
		return nil, (repaired and repaired.reason) or "repair_failed"
	end
	return {
		ok = true,
		duplicate = repaired.duplicate == true,
		pieceId = pieceId,
		transactionId = repaired.transactionId or transactionId,
		actorId = actorId,
		health = repaired.health,
		eventName = "BuildingRepaired",
		authority = "B1",
	}
end

return ProfessionAdapter

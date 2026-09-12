local Inventory = require(script.Parent.Parent.Parent.Inventory)

local I3Verifier = {}

local function countsMatch(accepted, yields)
	if type(accepted) ~= "table" or type(yields) ~= "table" then return false end
	for itemId, amount in pairs(yields) do
		if (accepted[itemId] or 0) ~= amount then return false end
	end
	for itemId, amount in pairs(accepted) do
		if (yields[itemId] or 0) ~= amount then return false end
	end
	return true
end

function I3Verifier.Verify(InventoryShadow, WorldItemAdapter, scope)
	local errors = {}
	InventoryShadow.Reset()

	local actorId = "i3-verifier-actor"
	local legacy = Inventory.new(8)

	-- 1) Committed Wood harvest → receipt → Convert yields → S4 accepted.
	local wood = InventoryShadow.ApplyCommittedHarvest({
		transactionId = "i3-tx-wood-1",
		actorId = actorId,
		worldTick = 42,
		cellKey = "2,1",
		worldResourceType = "Wood",
		actualWithdrawn = 1,
		context = {},
	})
	if not wood or not wood.ok or not wood.receipt or wood.receipt.provenance ~= "LivingWorld" then
		table.insert(errors, "wood_apply")
	else
		if not countsMatch(wood.accepted, wood.yields) then
			table.insert(errors, "s4_accepted_eq_yields")
		end
		if (wood.yields.Log or 0) ~= 3 or (wood.yields.Stick or 0) ~= 1 then
			table.insert(errors, "wood_convert_yields")
		end
		if InventoryShadow.Count(actorId, "Log") ~= 3 or InventoryShadow.Count(actorId, "Stick") ~= 1 then
			table.insert(errors, "s4_counts")
		end
	end

	-- Project LivingWorld units onto legacy Carry and assert Carry <= projection.
	if wood and wood.ok then
		legacy:Add("Wood", wood.projectedAmount)
		InventoryShadow.EnsureLegacyProjection(actorId, legacy)
		local okCap = InventoryShadow.LegacyNeverExceedsProjection(actorId, legacy)
		if not okCap or legacy:Get("Wood") ~= 1 then
			table.insert(errors, "carry_never_exceeds_s4")
		end
	end

	-- 2) Retry same transactionId must not duplicate S4 or projection.
	local woodRetry = InventoryShadow.ApplyCommittedHarvest({
		transactionId = "i3-tx-wood-1",
		actorId = actorId,
		worldTick = 42,
		cellKey = "2,1",
		worldResourceType = "Wood",
		actualWithdrawn = 1,
	})
	if not woodRetry or woodRetry.duplicate ~= true then
		table.insert(errors, "retry_duplicate_flag")
	end
	if InventoryShadow.Count(actorId, "Log") ~= 3 or InventoryShadow.ProjectedAmount(actorId, "Wood") ~= 1 then
		table.insert(errors, "retry_no_duplicate")
	end

	-- 3) Forage Food maps to ForageBush / ForageGreens — never bare Food→RawMeat.
	local food = InventoryShadow.ApplyCommittedHarvest({
		transactionId = "i3-tx-food-1",
		actorId = actorId,
		worldTick = 43,
		cellKey = "1,1",
		worldResourceType = "Food",
		actualWithdrawn = 1,
		-- source omitted on purpose: Apply defaults Forage context for W6 Food harvest.
	})
	if not food or not food.ok or food.receipt.sourceKind ~= "ForageBush" then
		table.insert(errors, "forage_source_kind")
	elseif (food.yields.ForageGreens or 0) ~= 3 or food.yields.RawMeat ~= nil then
		table.insert(errors, "forage_do_not_map_rawmeat")
	else
		legacy:Add("Food", food.projectedAmount)
	end

	-- Bare aggregate Food without forage context must stay unmapped at ResolveSourceKind.
	local bareKind, bareReason = WorldItemAdapter.ResolveSourceKind("Food", {})
	if bareKind ~= nil or bareReason ~= "unmapped_resource" then
		-- ResolveSourceKind("Food", {}) has no source — unmapped. (ApplyCommittedHarvest
		-- injects forage defaults for the W6 harvest path only.)
		table.insert(errors, "bare_food_unmapped")
	end

	-- 4) Deposit/delivery removes once from S4 + projection; retry is no-op.
	local beforeLog = InventoryShadow.Count(actorId, "Log")
	local deposit = InventoryShadow.RemoveLegacyProjection(actorId, "Wood", 1, "i3-dep-wood-1")
	local depositRetry = InventoryShadow.RemoveLegacyProjection(actorId, "Wood", 1, "i3-dep-wood-1")
	if not deposit or not deposit.ok or deposit.projectedRemoved ~= 1 then
		table.insert(errors, "deposit_remove")
	elseif InventoryShadow.Count(actorId, "Log") ~= beforeLog - 3 then
		table.insert(errors, "deposit_s4_items")
	elseif not depositRetry or depositRetry.duplicate ~= true then
		table.insert(errors, "deposit_retry_once")
	elseif InventoryShadow.ProjectedAmount(actorId, "Wood") ~= 0 then
		table.insert(errors, "deposit_projection")
	else
		legacy:Remove("Wood", 1)
	end

	-- 5) Mixed provenance: legacy-only Stone is untouched by LivingWorld projection.
	legacy:Add("Stone", 2)
	local proj = InventoryShadow.GetProjection(actorId)
	if proj.Stone ~= nil or legacy:Get("Stone") ~= 2 then
		table.insert(errors, "mixed_provenance")
	end
	if InventoryShadow.Count(actorId, "StoneChunk") ~= 0 then
		table.insert(errors, "legacy_not_in_s4")
	end

	-- 6) Efficiency cap ≤ 1 in Convert (adapter-level).
	local receipt = WorldItemAdapter.BuildReceipt({
		transactionId = "i3-eff-1",
		actorId = actorId,
		worldTick = 1,
		cellKey = "0,0",
		worldResourceType = "Wood",
		sourceKind = "Tree",
		actualWithdrawn = 1,
		toolClass = "axe",
		toolTier = 0,
	})
	local capped = WorldItemAdapter.Convert(receipt, {
		tool = { class = "axe", tier = 0, efficiency = 5 },
		worldUnitsPerAction = 1,
	})
	local baseline = WorldItemAdapter.Convert(receipt, {
		tool = { class = "axe", tier = 0, efficiency = 1 },
		worldUnitsPerAction = 1,
	})
	if not capped or not baseline then
		table.insert(errors, "efficiency_cap_convert")
	else
		for itemId, baseAmount in pairs(baseline) do
			if (capped[itemId] or 0) > baseAmount then
				table.insert(errors, "efficiency_cap_exceeded")
				break
			end
		end
	end

	local status = #errors == 0 and "PASS" or "ERROR"
	scope:SetAttribute("I3Status", status)
	scope:SetAttribute("I3Errors", table.concat(errors, ","))
	scope:SetAttribute("I3ShadowMode", "W6→Receipt→S4→CarryProjection")
	scope:SetAttribute("OwnsLegacyInventory", false)
	return status, errors
end

return I3Verifier

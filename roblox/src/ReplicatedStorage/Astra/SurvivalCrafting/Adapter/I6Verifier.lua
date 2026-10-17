-- I6 profession compose verifier:
-- Gatherer uses S2/S3 quotes without S withdrawing world resources;
-- Builder prefers B1 (P3 Construction remains compatibility dual-truth);
-- P7 XP only on outcome events (deduped); never global-reset live S4 after I3.
-- P6 roles unchanged by S/K; I3/I4/I5 non-regression.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local SurvivalCrafting = Astra:WaitForChild("SurvivalCrafting")
local Contract = require(SurvivalCrafting.Core.Contract)
local ProfessionAdapter = require(SurvivalCrafting.Adapter.ProfessionAdapter)
local P7OutcomeSink = require(SurvivalCrafting.Adapter.P7OutcomeSink)
local GatheringContracts = require(SurvivalCrafting.S2.GatheringContracts)
local ToolCatalog = require(SurvivalCrafting.S3.ToolCatalog)
local InventoryRegistry = require(SurvivalCrafting.S4.InventoryRegistry)
local ItemCatalog = require(SurvivalCrafting.S1.ItemCatalog)
local CraftingRuntime = require(SurvivalCrafting.Adapter.CraftingRuntime)
local CraftedBuildPartMapping = require(Astra.Building.CraftedBuildPartMapping)

local I6Verifier = {}

local VERIFY_PREFIX = "i6-"
local VERIFY_ACTORS = {
	"i6-gatherer",
	"i6-gatherer-tool",
	"i6-builder",
	"i6-repair",
	"i6-economy-a",
	"i6-economy-b",
	"i6-place-retry",
}

local function addError(errors, name)
	table.insert(errors, name)
end

local function survivalRoot()
	return Workspace:FindFirstChild(Contract.StateRootName)
end

local function scopeStatus(root, scopeName, attr)
	local scope = root and root:FindFirstChild(scopeName)
	return scope and scope:GetAttribute(attr) or nil
end

local function cleanupVerifierActors()
	if InventoryRegistry.ResetMatching then
		InventoryRegistry.ResetMatching(VERIFY_PREFIX)
	else
		for _, actorId in ipairs(VERIFY_ACTORS) do
			InventoryRegistry.Reset(actorId)
		end
	end
end

local function seedItem(actorId, itemId, quantity, prefix)
	local inv = InventoryRegistry.Get(actorId, 24)
	local catalog = ItemCatalog.Get(itemId)
	inv:Add({
		itemId = itemId,
		quantity = quantity,
		maxStack = catalog and catalog.maxStack or 50,
	}, prefix .. ":" .. itemId)
	return inv
end

function I6Verifier.Verify(deps, scope)
	deps = deps or {}
	local errors = {}

	-- Isolate verifier inventories: NEVER InventoryRegistry.Reset() global after I3 is live.
	local liveSentinel = "__i6_live_sentinel_probe__"
	local hadSentinel = InventoryRegistry.Has(liveSentinel)
	if not hadSentinel then
		InventoryRegistry.Get(liveSentinel, 1)
	end
	cleanupVerifierActors()

	-- 1) ProfessionAdapter does not steal Role/Skill authority and does not withdraw world.
	if ProfessionAdapter.WritesRoleSkillGoal() ~= false then
		addError(errors, "adapter_must_not_write_role_skill")
	end
	if ProfessionAdapter.WithdrawsWorldResources() ~= false then
		addError(errors, "adapter_must_not_withdraw_world")
	end
	if not ProfessionAdapter.IsActionAllowed("Gatherer", "HarvestQuote") then
		addError(errors, "gatherer_harvest_quote_allowed")
	end
	if not ProfessionAdapter.IsActionAllowed("Builder", "B1Place") then
		addError(errors, "builder_b1_place_allowed")
	end
	if ProfessionAdapter.IsActionAllowed("Gatherer", "B1Place") then
		addError(errors, "gatherer_must_not_place")
	end
	if ProfessionAdapter.IsActionAllowed("Scout", "W6Harvest") then
		addError(errors, "scout_must_not_harvest")
	end

	-- 2) Gatherer S2/S3 quotes (no world withdraw). No Virtual:axe invention.
	local woodQuote = ProfessionAdapter.QuoteGather("Wood", "i6-gatherer")
	if not woodQuote
		or woodQuote.withdrewWorld ~= false
		or woodQuote.sourceKind ~= "Tree"
	then
		addError(errors, "gather_wood_s2_s3_quote")
	end
	if woodQuote and (woodQuote.toolVirtual == true
		or (type(woodQuote.toolId) == "string" and string.find(woodQuote.toolId, "Virtual:", 1, true)))
	then
		addError(errors, "gather_no_virtual_tool")
	end
	-- Without a real S4 axe, Tree quote must fail (hand mismatch) rather than invent a tool.
	if woodQuote and woodQuote.ok ~= false then
		addError(errors, "gather_wood_requires_real_tool")
	end

	local foodQuote = ProfessionAdapter.QuoteGather("Food", "i6-gatherer")
	if not foodQuote
		or foodQuote.sourceKind ~= "ForageBush"
		or foodQuote.toolClass ~= "hand"
		or foodQuote.withdrewWorld ~= false
	then
		addError(errors, "gather_food_forage_quote")
	end

	-- Equipped StoneAxe in S4 should raise tool tier on quote.
	seedItem("i6-gatherer-tool", "StoneAxe", 1, "i6-seed-axe")
	local tooled = ProfessionAdapter.QuoteGather("Wood", "i6-gatherer-tool")
	if not tooled or tooled.toolId ~= "StoneAxe" or (tooled.toolTier or 0) < 2 then
		addError(errors, "gather_tool_from_s4")
	end

	local can, canReason = GatheringContracts.CanGather("Tree", { class = "axe", tier = 0 })
	if not can then
		addError(errors, "s2_tree_axe_tier0:" .. tostring(canReason))
	end
	if not ToolCatalog.Get("Hand") then
		addError(errors, "s3_hand_tool_missing")
	end

	local harvestCtx = ProfessionAdapter.HarvestContext("Wood", "i6-gatherer-tool")
	if not harvestCtx or harvestCtx.toolClass ~= "axe" or harvestCtx.sourceKind ~= "Tree" then
		addError(errors, "harvest_context_shape")
	end

	-- 3) Builder mutations go through B1 (stub lifecycle) + crafted mapping / S4 spend.
	-- Construction.lua remains compatibility fallback (dual-truth); do not claim sole B1 authority.
	if CraftedBuildPartMapping.Get("WoodFoundation") == nil then
		addError(errors, "crafted_mapping_missing")
	end

	seedItem("i6-builder", "WoodFoundation", 1, "i6-seed-foundation")
	local placeable = ProfessionAdapter.PickPlaceableBuildPart("i6-builder")
	if not placeable or placeable.itemId ~= "WoodFoundation" or placeable.pieceType ~= "FoundationSquare" then
		addError(errors, "builder_placeable_from_s4")
	end

	local placedCalls = {}
	local stubLifecycle = {
		PreviewRoot = function(pieceType, _position, _yaw)
			return {
				allowed = true,
				reason = nil,
				cframe = CFrame.new(0, 0, 0),
				surfaceY = 0,
				pieceType = pieceType,
			}
		end,
		PlaceRoot = function(pieceType, _position, _yaw, metadata)
			table.insert(placedCalls, {
				pieceType = pieceType,
				metadata = metadata,
			})
			return {
				id = "piece-i6-1",
				pieceType = pieceType,
				materialGrade = metadata and metadata.materialGrade,
			}, nil
		end,
		Repair = function(pieceId, economy, _requestedHealth, transactionId)
			if not economy or economy:CanAfford({ Wood = 1 }) ~= true then
				return { ok = false, reason = "cannot_afford" }
			end
			if economy:Spend({ Wood = 1 }) ~= true then
				return { ok = false, reason = "spend_failed" }
			end
			return {
				ok = true,
				duplicate = false,
				pieceId = pieceId,
				transactionId = transactionId,
				health = 100,
				maxHealth = 100,
			}
		end,
	}

	local placeResult, placeReason = ProfessionAdapter.PlaceCraftedPart(stubLifecycle, {
		actorId = "i6-builder",
		itemId = "WoodFoundation",
		position = Vector3.new(0, 0, 0),
		yawDegrees = 0,
		transactionId = "i6:place:1",
	})
	if not placeResult or placeResult.authority ~= "B1" or placeResult.pieceId ~= "piece-i6-1" then
		addError(errors, "builder_place_through_b1:" .. tostring(placeReason))
	end
	if #placedCalls ~= 1 or placedCalls[1].metadata == nil or placedCalls[1].metadata.transactionId ~= "i6:place:1" then
		addError(errors, "builder_place_metadata")
	end
	if InventoryRegistry.Get("i6-builder"):Count("WoodFoundation") ~= 0 then
		addError(errors, "builder_consumed_s4_part")
	end

	-- Place dedupe by transactionId (second call must not PlaceRoot again).
	local placeDup = ProfessionAdapter.PlaceCraftedPart(stubLifecycle, {
		actorId = "i6-builder",
		itemId = "WoodFoundation",
		position = Vector3.new(0, 0, 0),
		yawDegrees = 0,
		transactionId = "i6:place:1",
	})
	if not placeDup or placeDup.duplicate ~= true or #placedCalls ~= 1 then
		addError(errors, "builder_place_tx_dedupe")
	end

	-- Failed place + refund must clear consume memory (retry re-consumes; no free piece).
	seedItem("i6-place-retry", "WoodFoundation", 1, "i6-seed-retry")
	local failCalls = 0
	local failLifecycle = {
		PreviewRoot = function(pieceType, _position, _yaw)
			return {
				allowed = true,
				reason = nil,
				cframe = CFrame.new(0, 0, 0),
				surfaceY = 0,
				pieceType = pieceType,
			}
		end,
		PlaceRoot = function(_pieceType, _position, _yaw, _metadata)
			failCalls += 1
			if failCalls == 1 then
				return nil, "simulated_place_fail"
			end
			return { id = "piece-i6-retry", pieceType = "FoundationSquare" }, nil
		end,
	}
	local failResult, failReason = ProfessionAdapter.PlaceCraftedPart(failLifecycle, {
		actorId = "i6-place-retry",
		itemId = "WoodFoundation",
		position = Vector3.new(1, 0, 0),
		yawDegrees = 0,
		transactionId = "i6:place:retry",
	})
	if failResult ~= nil or failReason ~= "simulated_place_fail" then
		addError(errors, "builder_place_fail_refund:" .. tostring(failReason))
	end
	if InventoryRegistry.Get("i6-place-retry"):Count("WoodFoundation") ~= 1 then
		addError(errors, "builder_place_fail_restored_part")
	end
	local retryResult = ProfessionAdapter.PlaceCraftedPart(failLifecycle, {
		actorId = "i6-place-retry",
		itemId = "WoodFoundation",
		position = Vector3.new(1, 0, 0),
		yawDegrees = 0,
		transactionId = "i6:place:retry",
	})
	if not retryResult or retryResult.pieceId ~= "piece-i6-retry" then
		addError(errors, "builder_place_retry_reconsumes")
	end
	if InventoryRegistry.Get("i6-place-retry"):Count("WoodFoundation") ~= 0 then
		addError(errors, "builder_place_retry_consumed")
	end

	seedItem("i6-repair", "Log", 5, "i6-seed-log")
	local repairResult, repairReason = ProfessionAdapter.RepairPiece(stubLifecycle, {
		actorId = "i6-repair",
		pieceId = "piece-i6-1",
		transactionId = "i6:repair:1",
	})
	if not repairResult or repairResult.authority ~= "B1" or repairResult.eventName ~= "BuildingRepaired" then
		addError(errors, "builder_repair_through_b1:" .. tostring(repairReason))
	end

	-- Economy Remove/Add ids must include caller transactionId (second repair Spend must work).
	seedItem("i6-economy-a", "Log", 4, "i6-seed-econ-a")
	local repair2, repair2Reason = ProfessionAdapter.RepairPiece(stubLifecycle, {
		actorId = "i6-economy-a",
		pieceId = "piece-i6-econ",
		transactionId = "i6:repair:2",
	})
	local repair3, repair3Reason = ProfessionAdapter.RepairPiece(stubLifecycle, {
		actorId = "i6-economy-a",
		pieceId = "piece-i6-econ",
		transactionId = "i6:repair:3",
	})
	if not repair2 or not repair3 then
		addError(errors, "economy_tx_unique_spend:" .. tostring(repair2Reason) .. "/" .. tostring(repair3Reason))
	end
	if InventoryRegistry.Get("i6-economy-a"):Count("Log") ~= 2 then
		addError(errors, "economy_tx_spent_twice")
	end

	-- 4) P7 outcome sink: XP only on outcomes; Start/Step/pending rejected; dedupe by tx.
	local grants = {}
	local sink = P7OutcomeSink.new({
		grantFn = function(actorId, skill, amount, category, eventId, _meta)
			table.insert(grants, {
				actorId = actorId,
				skill = skill,
				amount = amount,
				category = category,
				eventId = eventId,
			})
			return amount
		end,
	})

	local rejectedStart = sink:Ingest({
		eventName = "CraftStarted",
		transactionId = "i6:craft:start",
		actorId = "i6-builder",
	})
	if rejectedStart.ok ~= false or rejectedStart.reason ~= "not_outcome_event" then
		addError(errors, "p7_reject_craft_started")
	end

	local rejectedStep = sink:Ingest({
		eventName = "Step",
		transactionId = "i6:craft:step",
		actorId = "i6-builder",
	})
	if rejectedStep.ok ~= false then
		addError(errors, "p7_reject_step")
	end

	local rejectedPending = sink:Ingest({
		eventName = "CraftPending",
		transactionId = "i6:craft:pending",
		actorId = "i6-builder",
	})
	if rejectedPending.ok ~= false then
		addError(errors, "p7_reject_pending")
	end

	local craftOutcome = sink:Ingest({
		eventName = "CraftCompleted",
		kind = "craft_completed",
		transactionId = "i6:craft:commit:1",
		actorId = "i6-builder",
	})
	if not craftOutcome.ok or craftOutcome.duplicate or (craftOutcome.granted or 0) <= 0 then
		addError(errors, "p7_craft_completed_grant")
	end

	local craftDup = sink:Ingest({
		eventName = "CraftCompleted",
		kind = "craft_completed",
		transactionId = "i6:craft:commit:1",
		actorId = "i6-builder",
	})
	if not craftDup.ok or craftDup.duplicate ~= true or (craftDup.granted or 0) ~= 0 then
		addError(errors, "p7_craft_dedupe")
	end

	-- StationProcessingCompleted accepted (wired like CraftCompleted; same tx dedupes).
	local stationOutcome = sink:Ingest({
		eventName = "StationProcessingCompleted",
		kind = "station_processing_completed",
		transactionId = "i6:station:commit:1",
		actorId = "i6-builder",
	})
	if not stationOutcome.ok or (stationOutcome.granted or 0) <= 0 then
		addError(errors, "p7_station_processing_completed")
	end
	if not P7OutcomeSink.FromStationProcessingCompleted then
		addError(errors, "p7_from_station_helper_missing")
	else
		local normalizedStation = P7OutcomeSink.FromStationProcessingCompleted({
			transactionId = "i6:station:norm:1",
			actorId = "i6-builder",
			station = "campfire",
			recipeId = "CookMeat",
		})
		if not normalizedStation or normalizedStation.eventName ~= "StationProcessingCompleted" then
			addError(errors, "p7_from_station_shape")
		end
		local handSkip = P7OutcomeSink.FromStationProcessingCompleted({
			transactionId = "i6:station:hand",
			actorId = "i6-builder",
			station = "hand",
		})
		if handSkip ~= nil then
			addError(errors, "p7_station_skips_hand")
		end
	end

	-- Harvest requires shadow.ok; shadowError / nil shadow are non-outcomes.
	local harvestBadShadow = P7OutcomeSink.FromHarvest({
		ok = true,
		duplicate = false,
		transactionId = "i6:harvest:bad",
		shadowError = "convert_failed",
		receipt = { actorId = "i6-gatherer", sourceKind = "Tree", worldResourceType = "Wood" },
	}, "i6-gatherer")
	if harvestBadShadow ~= nil then
		addError(errors, "p7_harvest_requires_shadow_ok")
	end
	local harvestNilShadow = P7OutcomeSink.FromHarvest({
		ok = true,
		duplicate = false,
		transactionId = "i6:harvest:nil-shadow",
		receipt = { actorId = "i6-gatherer", sourceKind = "Tree", worldResourceType = "Wood" },
	}, "i6-gatherer")
	if harvestNilShadow ~= nil then
		addError(errors, "p7_harvest_nil_shadow_rejected")
	end

	local harvestOutcome = sink:Ingest(P7OutcomeSink.FromHarvest({
		ok = true,
		duplicate = false,
		transactionId = "i6:harvest:1",
		shadow = { ok = true },
		receipt = { actorId = "i6-gatherer", sourceKind = "Tree", worldResourceType = "Wood" },
	}, "i6-gatherer"))
	if not harvestOutcome or not harvestOutcome.ok or harvestOutcome.skill ~= "Gatherer" then
		addError(errors, "p7_harvest_outcome")
	end

	local placeOutcome = sink:Ingest(P7OutcomeSink.FromBuilding(placeResult))
	if not placeOutcome or not placeOutcome.ok then
		addError(errors, "p7_place_outcome")
	end

	-- P3 complete under outcome-only: sink BuildingCompleted is the sole grant authority
	-- (SkillLearning skips builder_complete when P7_I6OutcomeOnly). One ingest → one grant.
	local p3GrantsBefore = #grants
	local p3Complete = sink:Ingest({
		eventName = "BuildingCompleted",
		kind = "building_completed",
		transactionId = "p3:complete:Shelter",
		actorId = "i6-builder",
	})
	local p3Dup = sink:Ingest({
		eventName = "BuildingCompleted",
		kind = "building_completed",
		transactionId = "p3:complete:Shelter",
		actorId = "i6-builder",
	})
	if not p3Complete or not p3Complete.ok or (p3Complete.granted or 0) <= 0 then
		addError(errors, "p7_p3_complete_grant_once")
	end
	if not p3Dup or p3Dup.duplicate ~= true or (p3Dup.granted or 0) ~= 0 then
		addError(errors, "p7_p3_complete_dedupe")
	end
	local p3GrantCount = 0
	for i = p3GrantsBefore + 1, #grants do
		if grants[i].eventId == "p3:complete:Shelter" then
			p3GrantCount += 1
		end
	end
	if p3GrantCount ~= 1 then
		addError(errors, "p7_p3_complete_single_authority")
	end

	if #grants < 4 then
		addError(errors, "p7_grant_count")
	end

	-- Prove I4 CraftCompleted naming still aligns.
	if CraftingRuntime.OutcomeEventName ~= "CraftCompleted" then
		addError(errors, "i4_outcome_event_name")
	end

	-- 5) I3/I4/I5 non-regression when scopes present.
	local root = survivalRoot()
	if root then
		local i3 = scopeStatus(root, "I3InventoryShadow", "I3Status")
		local i4 = scopeStatus(root, "I4CraftingRuntime", "I4Status")
		local i5 = scopeStatus(root, "I5BuildingCompose", "I5Status")
		if i3 ~= nil and i3 ~= "PASS" then
			addError(errors, "i3_regressed")
		end
		if i4 ~= nil and i4 ~= "PASS" then
			addError(errors, "i4_regressed")
		end
		if i5 ~= nil and i5 ~= "PASS" then
			addError(errors, "i5_regressed")
		end

		-- Station outcome wiring (compose sets attr; may still be pending if defer not run).
		local i6Scope = root:FindFirstChild("I6ProfessionIntegration") or scope
		if i6Scope and i6Scope:GetAttribute("I6WiredStationOutcome") == false
			and i6Scope:GetAttribute("I6StationOutcomeSkipReason") == nil
		then
			addError(errors, "station_outcome_unwired_undocumented")
		end
	end

	-- Assert live S4 registry was not globally wiped.
	if not InventoryRegistry.Has(liveSentinel) then
		addError(errors, "verifier_must_not_global_reset_s4")
	end
	if not hadSentinel then
		InventoryRegistry.Reset(liveSentinel)
	end

	-- Do not leave seeded i6-* actors in the live registry.
	cleanupVerifierActors()
	for _, actorId in ipairs(VERIFY_ACTORS) do
		if InventoryRegistry.Has(actorId) then
			addError(errors, "verifier_left_seeded_actor:" .. actorId)
		end
	end

	local status = #errors == 0 and "PASS" or "ERROR"
	if scope then
		scope:SetAttribute("I6Status", status)
		scope:SetAttribute("I6ErrorCount", #errors)
		scope:SetAttribute("I6Errors", table.concat(errors, ","))
		scope:SetAttribute("I6ProfessionMode", ProfessionAdapter.ProfessionMode)
		scope:SetAttribute("I6AdapterVersion", ProfessionAdapter.Version)
		scope:SetAttribute("I6WritesRoleSkillGoal", ProfessionAdapter.WritesRoleSkillGoal())
		scope:SetAttribute("I6WithdrawsWorld", ProfessionAdapter.WithdrawsWorldResources())
		scope:SetAttribute("I6IsolatedVerifierInventories", true)
		scope:SetAttribute("I6DualBuildingTruth", true)
		local stats = sink:GetStats()
		scope:SetAttribute("I6OutcomeGranted", stats.granted)
		scope:SetAttribute("I6OutcomeDuplicates", stats.duplicates)
		scope:SetAttribute("I6OutcomeRejected", stats.rejected)
	end

	return status == "PASS", errors, {
		status = status,
		errorCount = #errors,
		professionMode = ProfessionAdapter.ProfessionMode,
	}
end

return I6Verifier

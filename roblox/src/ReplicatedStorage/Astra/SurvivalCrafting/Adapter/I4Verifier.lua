local InventoryRegistry = require(script.Parent.Parent.S4.InventoryRegistry)
local ItemCatalog = require(script.Parent.Parent.S1.ItemCatalog)

local I4Verifier = {}

local function addItems(inv, items, prefix)
	for itemId, quantity in pairs(items) do
		local catalog = ItemCatalog.Get(itemId)
		inv:Add({
			itemId = itemId,
			quantity = quantity,
			maxStack = catalog and catalog.maxStack or 50,
		}, prefix .. ":" .. itemId)
	end
end

local function stepUntil(runtime, jobId, maxSteps)
	maxSteps = maxSteps or 64
	for tick = 1, maxSteps do
		local snap = runtime:SnapshotJob(jobId)
		if not snap then
			return nil, "missing_job"
		end
		if snap.job.state == "committed" then
			return snap, "committed"
		end
		if snap.job.state == "completed_pending_commit" and snap.meta.commitState == "pending" then
			return snap, "pending"
		end
		if snap.job.state == "completed_pending_commit" then
			local _, reason = runtime:TryCommit(jobId)
			if reason == "committed" then
				return runtime:SnapshotJob(jobId), "committed"
			end
			if reason == "output_full" or reason == "insufficient_fuel" then
				return runtime:SnapshotJob(jobId), "pending"
			end
		end
		runtime:Step(tick, 1)
	end
	return runtime:SnapshotJob(jobId), "timeout"
end

function I4Verifier.Verify(CraftingRuntime, scope)
	local errors = {}
	InventoryRegistry.Reset()

	-- 1) quote → job → single input spend → single output deposit
	local runtime = CraftingRuntime.new({ maxJobs = 8 })
	local actorId = "i4-actor"
	local inv = InventoryRegistry.Get(actorId, 24)
	addItems(inv, { Log = 2 }, "i4-seed-1")

	local quote = runtime:Quote({ actorId = actorId, recipeId = "plank_from_log", quantity = 1 })
	if not quote or not quote.inputsAvailable or quote.outputs.Plank ~= 2 then
		table.insert(errors, "quote_basic")
	end

	local started, startReason = runtime:Start({
		actorId = actorId,
		recipeId = "plank_from_log",
		quantity = 1,
		tick = 0,
	}, "i4-tx-plank-1")
	if not started or not started.ok or startReason == nil then
		table.insert(errors, "start_job")
	end

	local jobId = started and started.jobId
	local finished, finishReason = stepUntil(runtime, jobId, 16)
	if finishReason ~= "committed" or not finished or finished.job.state ~= "committed" then
		table.insert(errors, "commit_lifecycle")
	end
	if inv:Count("Log") ~= 1 or inv:Count("Plank") ~= 2 then
		table.insert(errors, "single_spend_deposit")
	end

	local outcomes = runtime:GetOutcomes()
	if #outcomes ~= 1 or outcomes[1].eventName ~= CraftingRuntime.OutcomeEventName then
		table.insert(errors, "outcome_event")
	elseif outcomes[1].eventName ~= "CraftCompleted" then
		table.insert(errors, "outcome_event_name")
	end

	-- 2) retry same start transactionId does not duplicate job / spend / output
	local retryStart = runtime:Start({
		actorId = actorId,
		recipeId = "plank_from_log",
		quantity = 1,
		tick = 0,
	}, "i4-tx-plank-1")
	if not retryStart or retryStart.duplicate ~= true then
		table.insert(errors, "start_retry_duplicate")
	end
	local commitRetry, commitRetryReason = runtime:TryCommit(jobId)
	if not commitRetry or commitRetry.duplicate ~= true or commitRetryReason ~= "committed" then
		table.insert(errors, "commit_retry_duplicate")
	end
	if inv:Count("Log") ~= 1 or inv:Count("Plank") ~= 2 or #runtime:GetOutcomes() ~= 1 then
		table.insert(errors, "retry_no_duplicate_items")
	end

	-- 3) pending-commit when output full (no lost items, no double spend)
	InventoryRegistry.Reset(actorId)
	local tiny = CraftingRuntime.new({ maxJobs = 4 })
	-- slotCapacity 1: seed Log fills the only slot; Plank output cannot deposit.
	local tinyInv = InventoryRegistry.Get(actorId, 1)
	addItems(tinyInv, { Log = 1 }, "i4-seed-full")
	local fullStart = tiny:Start({
		actorId = actorId,
		recipeId = "plank_from_log",
		quantity = 1,
		tick = 0,
		slotCapacity = 1,
	}, "i4-tx-full-1")
	if not fullStart or not fullStart.ok then
		table.insert(errors, "full_start")
	else
		local fullSnap, fullReason = stepUntil(tiny, fullStart.jobId, 16)
		if fullReason ~= "pending" then
			table.insert(errors, "pending_when_full")
		end
		if tinyInv:Count("Log") ~= 1 then
			table.insert(errors, "pending_no_spend")
		end
		if tinyInv:Count("Plank") ~= 0 then
			table.insert(errors, "pending_no_output")
		end
		if fullSnap and fullSnap.job.state ~= "completed_pending_commit" then
			table.insert(errors, "pending_state")
		end
		if #tiny:GetOutcomes() ~= 0 then
			table.insert(errors, "pending_no_outcome")
		end

		-- Free capacity by expanding: replace registry actor with larger inventory carrying same Log.
		-- Simulate by removing Log from full inv is wrong; instead create room via Remove then
		-- re-check: use a second actor inventory path — expand by Reset+reseed larger capacity
		-- while preserving the pending job's reserved inputs on the same registry actor.
		-- Practical path: Remove Log (manual), Add nothing, grow capacity by new Get with larger
		-- capacity does not resize. So manually free: craft uses reservation; spend has not
		-- happened. Clear the Log stack into a larger inventory instance by Reset is destructive.
		-- Instead: remove Log from tiny (1 slot free conceptually after remove), add Log back
		-- after increasing — InventoryV2 slotCapacity is fixed at construction.
		-- Work-around for verifier: use actor "i4-actor-full2" with capacity 4, transfer by
		-- counting — simplest accept path: pending asserted above; then Start a fresh runtime
		-- with room and prove commit succeeds separately (already covered in test 1).
		-- Additional: grow by swapping registry entry.
		InventoryRegistry.Reset(actorId)
		local roomy = InventoryRegistry.Get(actorId, 8)
		addItems(roomy, { Log = 1 }, "i4-seed-room")
		-- Rebind tiny's inventory view: same actorId now has room. Reservation still held.
		local flushed = tiny:TryCommit(fullStart.jobId)
		if not flushed or not flushed.ok or roomy:Count("Plank") ~= 2 or roomy:Count("Log") ~= 0 then
			table.insert(errors, "pending_flush_when_room")
		end
	end

	-- 4) S8 blocks unavailable recipes without spending
	InventoryRegistry.Reset()
	local locked = CraftingRuntime.new({ maxJobs = 4 })
	local lockedActor = "i4-locked"
	local lockedInv = InventoryRegistry.Get(lockedActor, 24)
	addItems(lockedInv, { IronOre = 4, Charcoal = 2 }, "i4-seed-lock")
	local beforeOre = lockedInv:Count("IronOre")
	local beforeChar = lockedInv:Count("Charcoal")
	local deniedQuote, deniedReason = locked:Quote({
		actorId = lockedActor,
		recipeId = "iron_smelting",
		station = "Furnace",
		quantity = 1,
	})
	if deniedQuote ~= nil or deniedReason ~= "research_locked" then
		table.insert(errors, "research_gate_quote")
	end
	local deniedStart, deniedStartReason = locked:Start({
		actorId = lockedActor,
		recipeId = "iron_smelting",
		station = "Furnace",
		quantity = 1,
		tick = 0,
	}, "i4-tx-locked-1")
	if deniedStart ~= nil or deniedStartReason ~= "research_locked" then
		table.insert(errors, "research_gate_start")
	end
	if lockedInv:Count("IronOre") ~= beforeOre or lockedInv:Count("Charcoal") ~= beforeChar then
		table.insert(errors, "research_no_spend")
	end

	-- Unlock via S8 Commit (with payment receipt) then craft should proceed.
	locked:GetResearch():Commit(lockedActor, "furnace", "i4-research-furnace", "payment:i4-1")
	local unlockedQuote = locked:Quote({
		actorId = lockedActor,
		recipeId = "iron_smelting",
		station = "Furnace",
		researchProfileId = lockedActor,
		quantity = 1,
		stationKey = "furnace-1",
	})
	-- Still needs fuel container for Furnace.
	local furnaceBox = locked:BindStationContainer("furnace-1", "Furnace")
	furnaceBox:Add("fuel", { itemId = "Charcoal", quantity = 2, maxStack = 100, tag = "fuel" }, "i4-fuel-seed")
	-- Recipe also consumes Charcoal as input from S4; keep S4 Charcoal.
	unlockedQuote = locked:Quote({
		actorId = lockedActor,
		recipeId = "iron_smelting",
		station = "Furnace",
		researchProfileId = lockedActor,
		quantity = 1,
		stationKey = "furnace-1",
	})
	if not unlockedQuote or not unlockedQuote.researchOk or not unlockedQuote.inputsAvailable then
		table.insert(errors, "research_unlock_quote")
	end

	-- 5) fuel/container effects apply once when stations/containers involved
	InventoryRegistry.Reset()
	local fueled = CraftingRuntime.new({ maxJobs = 4 })
	local fuelActor = "i4-fuel"
	local fuelInv = InventoryRegistry.Get(fuelActor, 24)
	addItems(fuelInv, { Log = 2 }, "i4-seed-fuel-log")
	local camp = fueled:BindStationContainer("camp-1", "Campfire")
	camp:Add("fuel", { itemId = "Charcoal", quantity = 1, maxStack = 100, tag = "fuel" }, "i4-camp-fuel")
	local fuelStart = fueled:Start({
		actorId = fuelActor,
		recipeId = "charcoal_from_log",
		station = "Campfire",
		stationKey = "camp-1",
		quantity = 1,
		tick = 0,
	}, "i4-tx-fuel-1")
	if not fuelStart or not fuelStart.ok then
		table.insert(errors, "fuel_start")
	else
		local fuelSnap, fuelFinish = stepUntil(fueled, fuelStart.jobId, 32)
		if fuelFinish ~= "committed" then
			table.insert(errors, "fuel_commit")
		end
		if fuelInv:Count("Log") ~= 0 or fuelInv:Count("Charcoal") ~= 2 then
			table.insert(errors, "fuel_io_counts")
		end
		local fuelBay = camp:Snapshot().fuel
		local fuelLeft = 0
		for _, stack in ipairs(fuelBay or {}) do
			fuelLeft += stack.quantity or 0
		end
		if fuelLeft ~= 0 then
			table.insert(errors, "fuel_consumed_once")
		end
		fueled:TryCommit(fuelStart.jobId)
		fuelBay = camp:Snapshot().fuel
		fuelLeft = 0
		for _, stack in ipairs(fuelBay or {}) do
			fuelLeft += stack.quantity or 0
		end
		if fuelLeft ~= 0 or fuelInv:Count("Charcoal") ~= 2 then
			table.insert(errors, "fuel_retry_once")
		end
		if fuelSnap and fuelSnap.meta and fuelSnap.meta.commitState ~= "committed" then
			table.insert(errors, "fuel_commit_state")
		end
	end

	-- 6) P7 is not awarded XP for queue-wait ticks — only CraftCompleted outcomes
	InventoryRegistry.Reset()
	local ticks = CraftingRuntime.new({ maxJobs = 4 })
	local tickActor = "i4-ticks"
	local tickInv = InventoryRegistry.Get(tickActor, 24)
	addItems(tickInv, { Log = 1 }, "i4-seed-ticks")
	local tickStart = ticks:Start({
		actorId = tickActor,
		recipeId = "plank_from_log",
		quantity = 1,
		tick = 0,
	}, "i4-tx-ticks-1")
	if tickStart and tickStart.ok then
		ticks:Step(1, 1) -- progress only; craftTicks=2 so still running
		if #ticks:GetOutcomes() ~= 0 then
			table.insert(errors, "no_outcome_on_running_tick")
		end
		stepUntil(ticks, tickStart.jobId, 16)
		if #ticks:GetOutcomes() ~= 1 or ticks:GetOutcomes()[1].eventName ~= "CraftCompleted" then
			table.insert(errors, "outcome_only_on_commit")
		end
	else
		table.insert(errors, "ticks_start")
	end

	local status = #errors == 0 and "PASS" or "ERROR"
	scope:SetAttribute("I4Status", status)
	scope:SetAttribute("I4Errors", table.concat(errors, ","))
	scope:SetAttribute("I4Scope", "I4CraftingRuntime")
	scope:SetAttribute("I4OutcomeEvent", CraftingRuntime.OutcomeEventName)
	scope:SetAttribute("I4Chain", "S4→S5→S6→S7→S10→S4")
	scope:SetAttribute("OwnsWorldResources", false)
	scope:SetAttribute("OwnsP7Xp", false)
	return status, errors
end

return I4Verifier

local RecipeGraph = require(script.Parent.Parent.S5.RecipeGraph)
local CraftQueue = require(script.Parent.Parent.S6.CraftQueue)
local StationCatalog = require(script.Parent.Parent.S7.StationCatalog)
local ResearchCatalog = require(script.Parent.Parent.S8.ResearchCatalog)
local ResearchRegistry = require(script.Parent.Parent.S8.ResearchRegistry)
local InventoryRegistry = require(script.Parent.Parent.S4.InventoryRegistry)
local ItemCatalog = require(script.Parent.Parent.S1.ItemCatalog)
local ContainerProfiles = require(script.Parent.Parent.S10.ContainerProfiles)
local StationContainer = require(script.Parent.Parent.S10.StationContainer)

-- I4 crafting orchestrator: S4 → S5 → S6 → S7 → S10 → S4 with atomic commit.
-- S8 gates recipe availability only (no Scrap spend without an external payment receipt).
-- Does not withdraw Living World resources; does not own P6/P7 Role/Skill/Goal.
local CraftingRuntime = {}
CraftingRuntime.__index = CraftingRuntime
CraftingRuntime.OutcomeEventName = "CraftCompleted"

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

local function scaleMap(map, quantity)
	local out = {}
	for itemId, amount in pairs(map or {}) do
		out[itemId] = math.max(0, math.floor(amount or 0)) * quantity
	end
	return out
end

local function itemHasTag(itemCatalog, itemId, tag)
	local item = itemCatalog.Get(itemId)
	if not item or type(item.tags) ~= "table" then
		return false
	end
	for _, value in ipairs(item.tags) do
		if value == tag then
			return true
		end
	end
	return false
end

function CraftingRuntime.new(opts)
	opts = opts or {}
	return setmetatable({
		recipeGraph = opts.recipeGraph or RecipeGraph,
		stationCatalog = opts.stationCatalog or StationCatalog,
		researchCatalog = opts.researchCatalog or ResearchCatalog,
		research = opts.research or ResearchRegistry.new(opts.researchCatalog or ResearchCatalog),
		inventoryRegistry = opts.inventoryRegistry or InventoryRegistry,
		itemCatalog = opts.itemCatalog or ItemCatalog,
		containerProfiles = opts.containerProfiles or ContainerProfiles,
		StationContainerClass = opts.StationContainer or StationContainer,
		queue = opts.queue or CraftQueue.new(opts.maxJobs or 32),
		jobs = {},
		startSeen = {},
		commitSeen = {},
		reservations = {},
		containers = {},
		outcomes = {},
		outcomeListeners = {},
	}, CraftingRuntime)
end

function CraftingRuntime:OnOutcome(listener)
	table.insert(self.outcomeListeners, listener)
end

function CraftingRuntime:GetOutcomes()
	return clone(self.outcomes)
end

function CraftingRuntime:GetQueue()
	return self.queue
end

function CraftingRuntime:GetResearch()
	return self.research
end

function CraftingRuntime:BindStationContainer(stationKey, profileId)
	assert(type(stationKey) == "string" and stationKey ~= "", "stationKey required")
	local profile = self.containerProfiles.Get(profileId)
	assert(profile, "unknown container profile")
	local container = self.StationContainerClass.new(profile)
	self.containers[stationKey] = container
	return container
end

function CraftingRuntime:GetContainer(stationKey)
	return self.containers[stationKey]
end

function CraftingRuntime:_reserved(actorId, itemId)
	local byActor = self.reservations[actorId]
	if not byActor then
		return 0
	end
	return byActor[itemId] or 0
end

function CraftingRuntime:_reserve(actorId, inputs)
	local byActor = self.reservations[actorId]
	if not byActor then
		byActor = {}
		self.reservations[actorId] = byActor
	end
	for itemId, amount in pairs(inputs or {}) do
		byActor[itemId] = (byActor[itemId] or 0) + amount
	end
end

function CraftingRuntime:_release(actorId, inputs)
	local byActor = self.reservations[actorId]
	if not byActor then
		return
	end
	for itemId, amount in pairs(inputs or {}) do
		local nextAmount = (byActor[itemId] or 0) - amount
		if nextAmount <= 0 then
			byActor[itemId] = nil
		else
			byActor[itemId] = nextAmount
		end
	end
end

function CraftingRuntime:_recipeAvailable(recipeId, profileId)
	local recipe = self.recipeGraph.Get(recipeId)
	if not recipe then
		return false, "unknown_recipe"
	end
	if (recipe.researchTier or 0) <= 0 then
		return true
	end
	local snapshot = self.research:Snapshot(profileId or "default")
	local unlocked = snapshot.unlocked or {}
	for nodeId, isOn in pairs(unlocked) do
		if isOn then
			local node = self.researchCatalog.Get(nodeId)
			if node then
				for _, unlockId in ipairs(node.unlocks or {}) do
					if unlockId == recipeId then
						return true
					end
				end
			end
		end
	end
	return false, "research_locked"
end

function CraftingRuntime:_canAcceptOutputs(inv, outputs)
	local snapshot = inv:Snapshot()
	local free = math.max(0, snapshot.slotCapacity - snapshot.usedSlots)
	local slotsNeeded = 0
	for itemId, amount in pairs(outputs or {}) do
		amount = math.max(0, math.floor(amount or 0))
		if amount > 0 then
			local catalog = self.itemCatalog.Get(itemId)
			local maxStack = catalog and catalog.maxStack or 50
			local room = 0
			for _, stack in ipairs(snapshot.slots) do
				if stack.itemId == itemId then
					room += math.max(0, (stack.maxStack or maxStack) - stack.quantity)
				end
			end
			local remaining = amount - room
			if remaining > 0 then
				slotsNeeded += math.ceil(remaining / maxStack)
			end
		end
	end
	return slotsNeeded <= free
end

function CraftingRuntime:_fuelAvailable(container, fuelRequired)
	if fuelRequired <= 0 then
		return true, nil
	end
	if not container then
		return false, "fuel_container_required"
	end
	local snap = container:Snapshot()
	local fuelStacks = snap.fuel or {}
	local total = 0
	for _, stack in ipairs(fuelStacks) do
		total += stack.quantity or 0
	end
	if total < fuelRequired then
		return false, "insufficient_fuel"
	end
	return true, nil
end

function CraftingRuntime:_consumeFuel(container, fuelRequired, commitKey)
	if fuelRequired <= 0 then
		return { removed = 0 }
	end
	local remaining = fuelRequired
	local removed = 0
	local snap = container:Snapshot()
	local fuelStacks = snap.fuel or {}
	-- Deterministic: spend from last stack backwards by itemId appearance order.
	local itemOrder = {}
	local seen = {}
	for i = #fuelStacks, 1, -1 do
		local itemId = fuelStacks[i].itemId
		if not seen[itemId] then
			seen[itemId] = true
			table.insert(itemOrder, itemId)
		end
	end
	for _, itemId in ipairs(itemOrder) do
		if remaining <= 0 then
			break
		end
		local result = container:Remove("fuel", itemId, remaining, commitKey .. ":fuel:" .. itemId)
		local took = result and result.removed or 0
		removed += took
		remaining -= took
	end
	return { removed = removed, missing = remaining }
end

function CraftingRuntime:Quote(spec)
	if type(spec) ~= "table" then
		return nil, "invalid_spec"
	end
	local actorId = spec.actorId
	local recipeId = spec.recipeId
	if type(actorId) ~= "string" or actorId == "" then
		return nil, "invalid_actorId"
	end
	if type(recipeId) ~= "string" or recipeId == "" then
		return nil, "invalid_recipeId"
	end
	local recipe = self.recipeGraph.Get(recipeId)
	if not recipe then
		return nil, "unknown_recipe"
	end

	local quantity = math.max(1, math.floor(spec.quantity or 1))
	local station = spec.station or recipe.station or "hand"
	if recipe.station == "hand" then
		station = "hand"
	elseif station ~= recipe.station then
		return nil, "wrong_station"
	elseif not self.stationCatalog.Get(station) then
		return nil, "unknown_station"
	elseif not self.stationCatalog.CanHostRecipe(station, recipe.station) then
		return nil, "station_cannot_host"
	end

	local available, lockReason = self:_recipeAvailable(recipeId, spec.researchProfileId)
	if not available then
		return nil, lockReason
	end

	local inputs = scaleMap(recipe.inputs, quantity)
	local outputs = scaleMap(recipe.outputs, quantity)
	local stationInfo = station ~= "hand" and self.stationCatalog.Get(station) or nil
	local fuelRequired = 0
	if stationInfo and (stationInfo.fuelSlots or 0) > 0 then
		fuelRequired = quantity
	end

	local inv = self.inventoryRegistry.Get(actorId, spec.slotCapacity)
	local missingInputs = {}
	for itemId, need in pairs(inputs) do
		local have = inv:Count(itemId) - self:_reserved(actorId, itemId)
		if have < need then
			missingInputs[itemId] = need - have
		end
	end

	local container = spec.stationKey and self.containers[spec.stationKey] or nil
	local fuelOk, fuelReason = self:_fuelAvailable(container, fuelRequired)

	return {
		recipeId = recipeId,
		actorId = actorId,
		quantity = quantity,
		station = station,
		inputs = inputs,
		outputs = outputs,
		craftTicks = recipe.craftTicks,
		totalTicks = recipe.craftTicks * quantity,
		fuelRequired = fuelRequired,
		researchOk = true,
		inputsAvailable = next(missingInputs) == nil,
		missingInputs = missingInputs,
		fuelOk = fuelOk,
		fuelReason = fuelReason,
		outputCapacityOk = self:_canAcceptOutputs(inv, outputs),
	}
end

function CraftingRuntime:Start(spec, transactionId)
	if type(spec) ~= "table" then
		return nil, "invalid_spec"
	end
	if type(transactionId) ~= "string" or transactionId == "" then
		return nil, "transaction_id_required"
	end
	if self.startSeen[transactionId] then
		local prior = clone(self.startSeen[transactionId])
		prior.duplicate = true
		return prior, "duplicate"
	end

	local quote, reason = self:Quote(spec)
	if not quote then
		return nil, reason
	end
	if not quote.inputsAvailable then
		return nil, "insufficient_inputs"
	end
	if quote.fuelRequired > 0 and not quote.fuelOk then
		return nil, quote.fuelReason or "insufficient_fuel"
	end

	local job, enqReason = self.queue:Enqueue({
		recipeId = quote.recipeId,
		quantity = quote.quantity,
		station = quote.station,
		craftTicks = quote.craftTicks,
		inputs = quote.inputs,
		outputs = quote.outputs,
	}, transactionId, spec.tick or 0)
	if not job then
		return nil, enqReason
	end

	self:_reserve(spec.actorId, quote.inputs)

	local meta = {
		jobId = job.id,
		actorId = spec.actorId,
		transactionId = transactionId,
		quote = quote,
		stationKey = spec.stationKey,
		researchProfileId = spec.researchProfileId or "default",
		commitState = "none",
	}
	self.jobs[job.id] = meta

	local result = {
		ok = true,
		duplicate = false,
		job = clone(job),
		quote = clone(quote),
		jobId = job.id,
		transactionId = transactionId,
	}
	self.startSeen[transactionId] = result
	return clone(result), enqReason or "queued"
end

function CraftingRuntime:_emitOutcome(payload)
	local outcome = clone(payload)
	outcome.eventName = CraftingRuntime.OutcomeEventName
	table.insert(self.outcomes, outcome)
	for _, listener in ipairs(self.outcomeListeners) do
		listener(clone(outcome))
	end
	return outcome
end

function CraftingRuntime:TryCommit(jobId)
	local meta = self.jobs[jobId]
	if not meta then
		return nil, "unknown_job"
	end
	local job = self.queue.byId[jobId]
	if not job then
		return nil, "job_not_found"
	end

	local commitKey = meta.transactionId .. ":commit"
	if self.commitSeen[commitKey] then
		local prior = clone(self.commitSeen[commitKey])
		prior.duplicate = true
		return prior, prior.ok and "committed" or (prior.reason or "duplicate")
	end
	if job.state == "committed" then
		return { ok = true, jobId = jobId, duplicate = true, state = "committed" }, "committed"
	end
	if job.state ~= "completed_pending_commit" then
		return nil, "not_ready"
	end

	local inv = self.inventoryRegistry.Get(meta.actorId)
	local outputs = meta.quote.outputs
	local inputs = meta.quote.inputs

	if not self:_canAcceptOutputs(inv, outputs) then
		meta.commitState = "pending"
		return {
			ok = false,
			pending = true,
			reason = "output_full",
			jobId = jobId,
			state = "completed_pending_commit",
			duplicate = false,
		}, "output_full"
	end

	local container = meta.stationKey and self.containers[meta.stationKey] or nil
	local fuelOk, fuelReason = self:_fuelAvailable(container, meta.quote.fuelRequired)
	if not fuelOk then
		meta.commitState = "pending"
		return {
			ok = false,
			pending = true,
			reason = fuelReason or "insufficient_fuel",
			jobId = jobId,
			state = "completed_pending_commit",
			duplicate = false,
		}, fuelReason or "insufficient_fuel"
	end

	-- Re-validate inputs are still covered (reservation + inventory).
	for itemId, need in pairs(inputs) do
		if inv:Count(itemId) < need then
			meta.commitState = "pending"
			return {
				ok = false,
				pending = true,
				reason = "insufficient_inputs",
				jobId = jobId,
				state = "completed_pending_commit",
				duplicate = false,
			}, "insufficient_inputs"
		end
	end

	local spent = {}
	for itemId, amount in pairs(inputs) do
		local result = inv:Remove(itemId, amount, commitKey .. ":spend:" .. itemId)
		spent[itemId] = result.removed
		if result.missing > 0 then
			-- Should be unreachable after pre-check; leave pending and do not mark committed.
			meta.commitState = "pending"
			return {
				ok = false,
				pending = true,
				reason = "spend_missing",
				jobId = jobId,
				spent = spent,
				state = "completed_pending_commit",
				duplicate = false,
			}, "spend_missing"
		end
	end

	local fuelResult = self:_consumeFuel(container, meta.quote.fuelRequired, commitKey)

	local deposited = {}
	local rejected = {}
	for itemId, amount in pairs(outputs) do
		local catalog = self.itemCatalog.Get(itemId)
		local result = inv:Add({
			itemId = itemId,
			quantity = amount,
			maxStack = catalog and catalog.maxStack or 50,
			metadata = {
				provenance = "Crafted",
				recipeId = meta.quote.recipeId,
				craftTransactionId = meta.transactionId,
			},
		}, commitKey .. ":out:" .. itemId)
		deposited[itemId] = result.accepted
		if result.rejected > 0 then
			rejected[itemId] = result.rejected
		end
	end

	if next(rejected) ~= nil then
		-- Pre-check failed race: keep pending. Spend already applied idempotently;
		-- retry will not re-spend and will re-attempt deposit via remembered Add.
		meta.commitState = "pending"
		return {
			ok = false,
			pending = true,
			reason = "output_rejected",
			jobId = jobId,
			spent = spent,
			deposited = deposited,
			rejected = rejected,
			state = "completed_pending_commit",
			duplicate = false,
		}, "output_rejected"
	end

	local committedJob = self.queue:Commit(jobId, true)
	self:_release(meta.actorId, inputs)
	meta.commitState = "committed"

	local outcome = self:_emitOutcome({
		jobId = jobId,
		transactionId = meta.transactionId,
		actorId = meta.actorId,
		recipeId = meta.quote.recipeId,
		station = meta.quote.station,
		quantity = meta.quote.quantity,
		inputs = clone(inputs),
		outputs = clone(outputs),
		spent = clone(spent),
		deposited = clone(deposited),
		fuelRemoved = fuelResult.removed or 0,
	})

	local result = {
		ok = true,
		pending = false,
		duplicate = false,
		jobId = jobId,
		state = committedJob and committedJob.state or "committed",
		spent = spent,
		deposited = deposited,
		fuelRemoved = fuelResult.removed or 0,
		outcome = outcome,
		outcomeEventName = CraftingRuntime.OutcomeEventName,
	}
	self.commitSeen[commitKey] = result
	return clone(result), "committed"
end

function CraftingRuntime:FlushPendingCommits()
	local results = {}
	for jobId, meta in pairs(self.jobs) do
		if meta.commitState == "pending" or meta.commitState == "none" then
			local job = self.queue.byId[jobId]
			if job and job.state == "completed_pending_commit" then
				local result, reason = self:TryCommit(jobId)
				table.insert(results, { jobId = jobId, result = result, reason = reason })
			end
		end
	end
	return results
end

function CraftingRuntime:Step(tick, workUnits)
	local job, reason = self.queue:Step(tick, workUnits)
	if reason == "ready_to_commit" and job then
		local commitResult, commitReason = self:TryCommit(job.id)
		return job, commitReason, commitResult
	end
	self:FlushPendingCommits()
	return job, reason, nil
end

function CraftingRuntime:SnapshotJob(jobId)
	local job = self.queue.byId[jobId]
	local meta = self.jobs[jobId]
	if not job then
		return nil
	end
	return {
		job = clone(job),
		meta = meta and {
			actorId = meta.actorId,
			transactionId = meta.transactionId,
			commitState = meta.commitState,
			stationKey = meta.stationKey,
			quote = clone(meta.quote),
		} or nil,
	}
end

function CraftingRuntime.ResetSharedInventory(actorId)
	InventoryRegistry.Reset(actorId)
end

return CraftingRuntime

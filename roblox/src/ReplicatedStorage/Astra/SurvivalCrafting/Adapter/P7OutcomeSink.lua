-- I6 P7 outcome sink: grants profession XP only on committed outcomes.
-- Deduped by transactionId. Never grants on Craft Start/Step/pending or build progress ticks.

local P7OutcomeSink = {}
P7OutcomeSink.__index = P7OutcomeSink
P7OutcomeSink.Version = "I6-2"

local DEFAULT_REWARDS = {
	harvest_committed = { skill = "Gatherer", amount = 1.6, category = "i6_harvest_committed" },
	craft_completed = { skill = "Builder", amount = 2.0, category = "i6_craft_completed" },
	station_processing_completed = { skill = "Builder", amount = 2.0, category = "i6_station_completed" },
	building_placed = { skill = "Builder", amount = 3.0, category = "i6_building_placed" },
	building_repaired = { skill = "Builder", amount = 2.2, category = "i6_building_repaired" },
	building_demolished = { skill = "Builder", amount = 1.0, category = "i6_building_demolished" },
	building_completed = { skill = "Builder", amount = 4.0, category = "i6_building_completed" },
}

local REJECT_EVENTS = {
	CraftStarted = true,
	CraftStep = true,
	CraftPending = true,
	Start = true,
	Step = true,
	pending = true,
	queued = true,
	running = true,
}

function P7OutcomeSink.new(opts)
	opts = opts or {}
	return setmetatable({
		seen = {},
		seenOrder = {},
		maxHistory = opts.maxHistory or 512,
		rewards = opts.rewards or DEFAULT_REWARDS,
		grantFn = opts.grantFn, -- function(actorId, skill, amount, category, eventId, meta)
		outcomes = {},
		rejected = 0,
		granted = 0,
		duplicates = 0,
	}, P7OutcomeSink)
end

function P7OutcomeSink:_remember(transactionId)
	if self.seen[transactionId] then
		return true
	end
	self.seen[transactionId] = true
	table.insert(self.seenOrder, transactionId)
	while #self.seenOrder > self.maxHistory do
		local old = table.remove(self.seenOrder, 1)
		self.seen[old] = nil
	end
	return false
end

function P7OutcomeSink:WasSeen(transactionId)
	return transactionId ~= nil and self.seen[transactionId] == true
end

function P7OutcomeSink:GetStats()
	return {
		granted = self.granted,
		duplicates = self.duplicates,
		rejected = self.rejected,
		outcomeCount = #self.outcomes,
	}
end

function P7OutcomeSink:GetOutcomes()
	local copy = {}
	for i, outcome in ipairs(self.outcomes) do
		copy[i] = outcome
	end
	return copy
end

local function normalizeKind(kind)
	if type(kind) ~= "string" then
		return nil
	end
	return string.lower(kind)
end

function P7OutcomeSink:IsOutcomeEvent(eventName)
	if type(eventName) ~= "string" or eventName == "" then
		return false
	end
	if REJECT_EVENTS[eventName] then
		return false
	end
	local lower = string.lower(eventName)
	if REJECT_EVENTS[lower] then
		return false
	end
	if string.find(lower, "start", 1, true)
		or string.find(lower, "step", 1, true)
		or string.find(lower, "pending", 1, true)
		or string.find(lower, "queued", 1, true)
		or string.find(lower, "running", 1, true)
	then
		-- Allow *Completed / *Committed endings even if they contain no start/step.
		if not string.find(lower, "complete", 1, true) and not string.find(lower, "commit", 1, true) then
			return false
		end
	end
	return true
end

function P7OutcomeSink:Ingest(raw)
	if type(raw) ~= "table" then
		self.rejected += 1
		return { ok = false, reason = "invalid_payload" }
	end

	local eventName = raw.eventName or raw.event or raw.type
	if not self:IsOutcomeEvent(eventName) then
		self.rejected += 1
		return { ok = false, reason = "not_outcome_event", eventName = eventName }
	end

	local transactionId = raw.transactionId
	if type(transactionId) ~= "string" or transactionId == "" then
		self.rejected += 1
		return { ok = false, reason = "missing_transactionId" }
	end

	if self:_remember(transactionId) then
		self.duplicates += 1
		return { ok = true, duplicate = true, transactionId = transactionId, granted = 0 }
	end

	local kind = normalizeKind(raw.kind or raw.outcomeKind or eventName)
	local rewardKey = nil
	if kind == "harvest_committed" or kind == "harvestcommitted" or eventName == "HarvestCommitted" then
		rewardKey = "harvest_committed"
	elseif kind == "craft_completed" or kind == "craftcompleted" or eventName == "CraftCompleted" then
		rewardKey = "craft_completed"
	elseif kind == "station_processing_completed" or eventName == "StationProcessingCompleted" then
		rewardKey = "station_processing_completed"
	elseif kind == "building_placed" or eventName == "BuildingPlaced" or eventName == "building.piece.placed" then
		rewardKey = "building_placed"
	elseif kind == "building_repaired" or eventName == "BuildingRepaired" or eventName == "building.piece.repaired" then
		rewardKey = "building_repaired"
	elseif kind == "building_demolished" or eventName == "BuildingDemolished" or eventName == "building.piece.demolished" then
		rewardKey = "building_demolished"
	elseif kind == "building_completed" or eventName == "BuildingCompleted" then
		rewardKey = "building_completed"
	end

	local reward = rewardKey and self.rewards[rewardKey]
	if not reward then
		self.rejected += 1
		return { ok = false, reason = "unknown_outcome_kind", kind = kind, eventName = eventName }
	end

	local actorId = raw.actorId or raw.agentName or raw.worker
	local skill = raw.skill or reward.skill
	local amount = tonumber(raw.amount) or reward.amount
	local category = raw.category or reward.category

	local granted = 0
	if self.grantFn and type(actorId) == "string" and actorId ~= "" and amount > 0 then
		granted = self.grantFn(actorId, skill, amount, category, transactionId, {
			eventName = eventName,
			kind = rewardKey,
			meta = raw,
		}) or 0
	end

	local record = {
		ok = true,
		duplicate = false,
		transactionId = transactionId,
		actorId = actorId,
		skill = skill,
		amount = amount,
		granted = granted,
		category = category,
		eventName = eventName,
		kind = rewardKey,
	}
	table.insert(self.outcomes, record)
	self.granted += 1
	return record
end

function P7OutcomeSink.FromCraftCompleted(outcome)
	if type(outcome) ~= "table" then
		return nil
	end
	return {
		eventName = outcome.eventName or "CraftCompleted",
		kind = "craft_completed",
		transactionId = outcome.transactionId or outcome.commitTransactionId,
		actorId = outcome.actorId,
		recipeId = outcome.recipeId,
	}
end

-- Station-hosted I4 commits (same commit authority; eventName differs for soak visibility).
function P7OutcomeSink.FromStationProcessingCompleted(outcome)
	if type(outcome) ~= "table" then
		return nil
	end
	local station = outcome.station
	if type(station) ~= "string" or station == "" or station == "hand" then
		return nil
	end
	return {
		eventName = outcome.eventName or "StationProcessingCompleted",
		kind = "station_processing_completed",
		transactionId = outcome.transactionId or outcome.commitTransactionId,
		actorId = outcome.actorId,
		recipeId = outcome.recipeId,
		station = station,
	}
end

function P7OutcomeSink.FromHarvest(tx, actorId)
	if type(tx) ~= "table" or not tx.ok or tx.duplicate then
		return nil
	end
	-- Require committed I3 shadow.ok. shadowError / nil shadow are non-outcomes.
	if tx.shadowError ~= nil then
		return nil
	end
	if not (tx.shadow and tx.shadow.ok) then
		return nil
	end
	return {
		eventName = "HarvestCommitted",
		kind = "harvest_committed",
		transactionId = tx.transactionId,
		actorId = actorId or (tx.receipt and tx.receipt.actorId),
		worldResourceType = tx.receipt and tx.receipt.worldResourceType,
		sourceKind = tx.receipt and tx.receipt.sourceKind,
	}
end

function P7OutcomeSink.FromBuilding(result)
	if type(result) ~= "table" or not result.ok then
		return nil
	end
	if result.duplicate then
		return {
			eventName = result.eventName or "BuildingPlaced",
			kind = result.kind,
			transactionId = result.transactionId,
			actorId = result.actorId,
			duplicateHint = true,
		}
	end
	return {
		eventName = result.eventName,
		kind = result.kind
			or (result.eventName == "BuildingRepaired" and "building_repaired")
			or (result.eventName == "BuildingDemolished" and "building_demolished")
			or "building_placed",
		transactionId = result.transactionId,
		actorId = result.actorId,
		pieceId = result.pieceId,
	}
end

return P7OutcomeSink

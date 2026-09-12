local SharedKnowledge = {}

local observations = {}
local seen = {}

local function copyObservation(observation)
    return {
        id = observation.id,
        type = observation.type,
        subtype = observation.subtype,
        resourceId = observation.resourceId,
        position = observation.position,
        sourceAgentId = observation.sourceAgentId,
        observedTick = observation.observedTick,
        createdTick = observation.createdTick,
        confidence = observation.confidence,
        provenance = observation.provenance,
        expiresTick = observation.expiresTick,
        valid = observation.valid ~= false,
    }
end

function SharedKnowledge.Publish(observation, currentTick, ttl)
    if not observation or not observation.id then
        return false, "invalid"
    end

    currentTick = currentTick or observation.createdTick or 0
    if seen[observation.id] then
        return false, "duplicate"
    end

    local stored = copyObservation(observation)
    stored.createdTick = stored.createdTick or currentTick
    stored.expiresTick = stored.expiresTick or (currentTick + (ttl or 10))
    stored.valid = observation.valid ~= false

    seen[stored.id] = true
    observations[stored.id] = stored
    return true, stored
end

function SharedKnowledge.Get(id, currentTick)
    local item = observations[id]
    if not item or item.valid == false then
        return nil
    end
    if currentTick and item.expiresTick and currentTick > item.expiresTick then
        return nil
    end
    return item
end

function SharedKnowledge.GetResource(resourceId, currentTick)
    local best = nil
    for _, item in pairs(observations) do
        if item.valid ~= false and item.type == "resource" and item.resourceId == resourceId then
            if (not currentTick or not item.expiresTick or currentTick <= item.expiresTick)
                and (not best or item.observedTick > best.observedTick or item.confidence > best.confidence) then
                best = item
            end
        end
    end
    return best
end

function SharedKnowledge.GetKnownResources(currentTick)
    local result = {}
    local newestByResource = {}

    for _, item in pairs(observations) do
        if item.valid ~= false and item.type == "resource"
            and (not currentTick or not item.expiresTick or currentTick <= item.expiresTick) then
            local old = newestByResource[item.resourceId]
            if not old or item.observedTick > old.observedTick then
                newestByResource[item.resourceId] = item
            end
        end
    end

    for _, item in pairs(newestByResource) do
        table.insert(result, item)
    end

    table.sort(result, function(a, b)
        if a.observedTick == b.observedTick then
            return a.resourceId < b.resourceId
        end
        return a.observedTick > b.observedTick
    end)

    return result
end

function SharedKnowledge.InvalidateByResource(resourceId, currentTick, sourceAgentId)
    local count = 0
    for _, item in pairs(observations) do
        if item.type == "resource" and item.resourceId == resourceId and item.valid ~= false then
            item.valid = false
            item.invalidatedTick = currentTick
            item.invalidatedBy = sourceAgentId
            count += 1
        end
    end
    return count
end

function SharedKnowledge.Cleanup(currentTick)
    local expired = 0
    for id, item in pairs(observations) do
        if item.expiresTick and currentTick > item.expiresTick then
            observations[id] = nil
            expired += 1
        end
    end
    return expired
end

function SharedKnowledge.ActiveCount(currentTick)
    return #SharedKnowledge.GetKnownResources(currentTick)
end

function SharedKnowledge.ResetForTests()
    observations = {}
    seen = {}
end

return SharedKnowledge

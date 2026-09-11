local Communication = {}

local inboxes = setmetatable({}, { __mode = "k" })
local seenMessages = {}
local sequence = 0
local nextCleanupTick = 0

local function getInbox(agent)
    local inbox = inboxes[agent]
    if not inbox then
        inbox = {}
        inboxes[agent] = inbox
    end
    return inbox
end

local function cleanupSeen(currentTick, config)
    if currentTick < nextCleanupTick then
        return 0
    end

    local removed = 0
    for messageId, expiresTick in pairs(seenMessages) do
        if currentTick > expiresTick then
            seenMessages[messageId] = nil
            removed += 1
        end
    end

    nextCleanupTick = currentTick + (config.MessageRegistryCleanupIntervalTicks or 6)
    return removed
end

local function nextMessageId(fromAgent, tick, messageType, observationId)
    sequence += 1
    return string.format("%s:%s:%s:%d:%d", fromAgent.Name, messageType, observationId or "none", tick or 0, sequence)
end

function Communication.Send(fromAgent, toAgent, tick, messageType, payload, config)
    if not fromAgent or not toAgent or not toAgent.Parent then
        return false
    end

    cleanupSeen(tick or 0, config)

    local messageId = nextMessageId(fromAgent, tick, messageType, payload and payload.observationId)
    if seenMessages[messageId] then
        return false
    end

    local registryTTL = config.MessageRegistryTTL or ((config.MessageTTL or 8) * 3)
    seenMessages[messageId] = (tick or 0) + registryTTL

    local inbox = getInbox(toAgent)
    if #inbox >= (config.MaxMessageQueueSize or 50) then
        table.remove(inbox, 1)
        toAgent:SetAttribute("DroppedInboxMessages", (toAgent:GetAttribute("DroppedInboxMessages") or 0) + 1)
    end

    table.insert(inbox, {
        messageId = messageId,
        tick = tick,
        expiresTick = tick + (config.MessageTTL or 8),
        from = fromAgent.Name,
        type = messageType,
        payload = payload,
        provenance = payload and payload.provenance or "communication",
    })

    toAgent:SetAttribute("LastHeardFrom", fromAgent.Name)
    toAgent:SetAttribute("LastHeardType", messageType)
    toAgent:SetAttribute("LastHeardTick", tick)
    return true
end

function Communication.BroadcastResourceObservation(fromAgent, agentsFolder, tick, observation, config)
    local sent = 0
    for _, other in ipairs(agentsFolder:GetChildren()) do
        if other ~= fromAgent and other:IsA("Model") and other:GetAttribute("Role") == "Gatherer" then
            if Communication.Send(fromAgent, other, tick, "resource_report", {
                observationId = observation.id,
                resourceId = observation.resourceId,
                resourceType = observation.subtype,
                position = observation.position,
                observedTick = observation.observedTick,
                confidence = config.ReportedResourceConfidence or 0.75,
                provenance = "communication",
            }, config) then
                sent += 1
            end
        end
    end
    return sent
end

function Communication.BroadcastStatus(fromAgent, agentsFolder, tick, messageType, payload, config)
    local sent = 0
    for _, other in ipairs(agentsFolder:GetChildren()) do
        if other ~= fromAgent and other:IsA("Model") then
            if Communication.Send(fromAgent, other, tick, messageType, payload, config) then
                sent += 1
            end
        end
    end
    return sent
end

function Communication.ReceiveAll(agent, currentTick, config)
    cleanupSeen(currentTick or 0, config or {})

    local inbox = getInbox(agent)
    inboxes[agent] = {}

    local valid = {}
    local expired = 0
    for _, message in ipairs(inbox) do
        if message.expiresTick and currentTick > message.expiresTick then
            expired += 1
        else
            table.insert(valid, message)
        end
    end

    return valid, expired
end

function Communication.Cleanup(currentTick, config)
    return cleanupSeen(currentTick or 0, config or {})
end

function Communication.RegistrySize()
    local count = 0
    for _ in pairs(seenMessages) do
        count += 1
    end
    return count
end

function Communication.TotalInboxSize()
    local total = 0
    for _, inbox in pairs(inboxes) do
        total += #inbox
    end
    return total
end

return Communication

local Communication = {}

local inboxes = setmetatable({}, { __mode = "k" })

local function getInbox(agent)
    local inbox = inboxes[agent]
    if not inbox then
        inbox = {}
        inboxes[agent] = inbox
    end
    return inbox
end

function Communication.Send(fromAgent, toAgent, tick, messageType, payload)
    if not fromAgent or not toAgent or not toAgent.Parent then
        return false
    end

    local inbox = getInbox(toAgent)
    table.insert(inbox, {
        tick = tick,
        from = fromAgent.Name,
        type = messageType,
        payload = payload,
    })

    toAgent:SetAttribute("LastHeardFrom", fromAgent.Name)
    toAgent:SetAttribute("LastHeardType", messageType)
    toAgent:SetAttribute("LastHeardTick", tick)

    return true
end

function Communication.BroadcastResourceReport(fromAgent, agentsFolder, tick, resource, position, maxDistance)
    local sent = 0
    local fromRoot = fromAgent:FindFirstChild("HumanoidRootPart")
    if not fromRoot then
        return 0
    end

    for _, other in ipairs(agentsFolder:GetChildren()) do
        if other ~= fromAgent and other:IsA("Model") and other:GetAttribute("Role") == "Gatherer" then
            local otherRoot = other:FindFirstChild("HumanoidRootPart")
            if otherRoot and (otherRoot.Position - fromRoot.Position).Magnitude <= maxDistance then
                if Communication.Send(fromAgent, other, tick, "resource_report", {
                    resourceName = resource.Name,
                    position = position,
                }) then
                    sent += 1
                end
            end
        end
    end

    return sent
end

function Communication.ReceiveAll(agent)
    local inbox = getInbox(agent)
    local messages = inboxes[agent] or {}
    inboxes[agent] = {}
    return messages
end

return Communication

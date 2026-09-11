local WorldSimIntentQueue = {}

function WorldSimIntentQueue.Capture(agentsFolder, tick, queueFolder)
    local intents = {}
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            table.insert(intents, {
                agentId = agent.Name,
                role = agent:GetAttribute("Role") or "Unknown",
                goal = agent:GetAttribute("Goal") or "Unknown",
                score = agent:GetAttribute("GoalScore") or 0,
                critical = agent:GetAttribute("SurvivalCritical") == true,
            })
        end
    end

    table.sort(intents, function(a, b)
        if a.critical ~= b.critical then return a.critical end
        if a.score ~= b.score then return a.score > b.score end
        return a.agentId < b.agentId
    end)

    local order = {}
    for index, intent in ipairs(intents) do
        table.insert(order, intent.agentId .. ":" .. intent.goal)
        local agent = agentsFolder:FindFirstChild(intent.agentId)
        if agent then agent:SetAttribute("WorldIntentOrder", index) end
    end

    queueFolder:SetAttribute("Tick", tick)
    queueFolder:SetAttribute("IntentCount", #intents)
    queueFolder:SetAttribute("DeterministicOrder", table.concat(order, ","))
    queueFolder:SetAttribute("TopIntent", #intents > 0 and order[1] or "None")
    return intents
end

return WorldSimIntentQueue

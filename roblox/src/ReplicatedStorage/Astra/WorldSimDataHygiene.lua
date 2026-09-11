local WorldSimDataHygiene = {}

local function countModels(folder)
    local count = 0
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then count += 1 end
    end
    return count
end

function WorldSimDataHygiene.Update(folders, simRoot, hygieneFolder)
    local issues = {}
    local agentCount = countModels(folders.agents)
    local resourceCount = #folders.resources:GetChildren()
    local structureCount = #folders.structures:GetChildren()
    local replay = simRoot:FindFirstChild("Replay")
    local relation = simRoot:FindFirstChild("Relationships")

    if agentCount <= 0 then table.insert(issues, "no_agents") end
    if resourceCount > 200 then table.insert(issues, "resource_count_high") end
    if structureCount > 100 then table.insert(issues, "structure_count_high") end
    if replay and (replay:GetAttribute("HistoryCount") or 0) > 240 then table.insert(issues, "replay_over_cap") end
    if relation and (relation:GetAttribute("DirectedRelationCount") or 0) > math.max(1, agentCount) * 24 then
        table.insert(issues, "relationship_over_cap")
    end

    local invalidAgents = 0
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            if not agent:FindFirstChild("HumanoidRootPart") or not agent:FindFirstChildOfClass("Humanoid") then
                invalidAgents += 1
            end
        end
    end
    if invalidAgents > 0 then table.insert(issues, "invalid_agents") end

    hygieneFolder:SetAttribute("Status", #issues == 0 and "HEALTHY" or "WARN")
    hygieneFolder:SetAttribute("IssueCount", #issues)
    hygieneFolder:SetAttribute("Issues", table.concat(issues, ","))
    hygieneFolder:SetAttribute("AgentCount", agentCount)
    hygieneFolder:SetAttribute("InvalidAgentCount", invalidAgents)
    hygieneFolder:SetAttribute("ResourceCount", resourceCount)
    hygieneFolder:SetAttribute("StructureCount", structureCount)
    return { healthy = #issues == 0, issues = issues }
end

return WorldSimDataHygiene

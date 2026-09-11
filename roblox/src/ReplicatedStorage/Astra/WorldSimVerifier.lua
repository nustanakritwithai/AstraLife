local WorldSimVerifier = {}

local REQUIRED_FOLDERS = {
    "Market", "Settlement", "Relationships", "Territory", "Routes", "Organization", "Metrics", "Replay",
}

local REQUIRED_AGENT_ATTRS = {
    "Trait_Bravery", "Trait_Greed", "Trait_Loyalty", "Trait_Ambition", "Trait_RiskTolerance", "Trait_Discipline",
    "DominantMotive", "InjurySeverity", "WorldMod_Work", "SimulationLOD", "OrganizationId",
}

function WorldSimVerifier.Update(folders, simRoot)
    local failures = {}

    if (simRoot:GetAttribute("LastProcessedTick") or -1) < 0 then table.insert(failures, "tick") end
    local fingerprint = simRoot:GetAttribute("LastFingerprint")
    if type(fingerprint) ~= "string" or fingerprint == "" then table.insert(failures, "fingerprint") end

    for _, name in ipairs(REQUIRED_FOLDERS) do
        if not simRoot:FindFirstChild(name) then table.insert(failures, "folder:" .. name) end
    end

    local market = simRoot:FindFirstChild("Market")
    if market and market:GetAttribute("Price_Food") == nil then table.insert(failures, "market") end
    local settlement = simRoot:FindFirstChild("Settlement")
    if settlement and settlement:GetAttribute("Stability") == nil then table.insert(failures, "settlement") end
    local territory = simRoot:FindFirstChild("Territory")
    if territory and (territory:GetAttribute("ClaimedCellCount") or 0) < 1 then table.insert(failures, "territory") end
    local routes = simRoot:FindFirstChild("Routes")
    if routes and (routes:GetAttribute("NodeCount") or 0) < 1 then table.insert(failures, "routes") end
    local replay = simRoot:FindFirstChild("Replay")
    if replay and (replay:GetAttribute("HistoryCount") or 0) < 1 then table.insert(failures, "replay") end

    local agentCount = 0
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            agentCount += 1
            for _, attribute in ipairs(REQUIRED_AGENT_ATTRS) do
                if agent:GetAttribute(attribute) == nil then
                    table.insert(failures, agent.Name .. ":" .. attribute)
                    break
                end
            end
        end
    end
    if agentCount < 1 then table.insert(failures, "agents") end

    local status = #failures == 0 and "PASS" or "RUNNING"
    folders.state:SetAttribute("WorldSimCoreStatus", status)
    simRoot:SetAttribute("VerifierStatus", status)
    simRoot:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return WorldSimVerifier

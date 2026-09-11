local WorldSimVerifier = {}

local REQUIRED_FOLDERS = {
    "Market", "Labor", "Ecology", "Threats", "Settlement", "Relationships",
    "Territory", "Routes", "Organization", "Population", "Migration", "Governance",
    "Recruitment", "Zones", "Hydrology", "Situation", "IntentQueue", "DataHygiene",
    "Metrics", "Replay",
}

local REQUIRED_AGENT_ATTRS = {
    "Trait_Bravery", "Trait_Greed", "Trait_Loyalty", "Trait_Ambition", "Trait_RiskTolerance", "Trait_Discipline",
    "DominantMotive", "InjurySeverity", "WorldMod_Work", "SimulationLOD", "OrganizationId", "LaborBestProfession",
    "PsychologicalFear", "Morale", "MigrationPressure", "WorldZone", "WaterAccess", "WorldIntentOrder",
}

function WorldSimVerifier.Update(folders, simRoot)
    local failures = {}

    if (simRoot:GetAttribute("LastProcessedTick") or -1) < 0 then table.insert(failures, "tick") end
    local fingerprint = simRoot:GetAttribute("LastFingerprint")
    if type(fingerprint) ~= "string" or fingerprint == "" then table.insert(failures, "fingerprint") end
    if (simRoot:GetAttribute("LastSerializedBytes") or 0) <= 0 then table.insert(failures, "serialization") end

    for _, name in ipairs(REQUIRED_FOLDERS) do
        if not simRoot:FindFirstChild(name) then table.insert(failures, "folder:" .. name) end
    end

    local market = simRoot:FindFirstChild("Market")
    if market and market:GetAttribute("Price_Food") == nil then table.insert(failures, "market") end
    local labor = simRoot:FindFirstChild("Labor")
    if labor and labor:GetAttribute("HighestDemandProfession") == nil then table.insert(failures, "labor") end
    local ecology = simRoot:FindFirstChild("Ecology")
    if ecology and ecology:GetAttribute("ActiveResourceTotal") == nil then table.insert(failures, "ecology") end
    local threats = simRoot:FindFirstChild("Threats")
    if threats and threats:GetAttribute("ThreatPressure") == nil then table.insert(failures, "threats") end
    local settlement = simRoot:FindFirstChild("Settlement")
    if settlement and settlement:GetAttribute("Stability") == nil then table.insert(failures, "settlement") end
    local territory = simRoot:FindFirstChild("Territory")
    if territory and (territory:GetAttribute("ClaimedCellCount") or 0) < 1 then table.insert(failures, "territory") end
    local routes = simRoot:FindFirstChild("Routes")
    if routes and (routes:GetAttribute("NodeCount") or 0) < 1 then table.insert(failures, "routes") end
    local population = simRoot:FindFirstChild("Population")
    if population and population:GetAttribute("Total") == nil then table.insert(failures, "population") end
    local migration = simRoot:FindFirstChild("Migration")
    if migration and migration:GetAttribute("AveragePressure") == nil then table.insert(failures, "migration") end
    local governance = simRoot:FindFirstChild("Governance")
    if governance and governance:GetAttribute("Legitimacy") == nil then table.insert(failures, "governance") end
    local recruitment = simRoot:FindFirstChild("Recruitment")
    if recruitment and recruitment:GetAttribute("HighestNeedRole") == nil then table.insert(failures, "recruitment") end
    local zones = simRoot:FindFirstChild("Zones")
    if zones and zones:GetAttribute("SafeAgentCount") == nil then table.insert(failures, "zones") end
    local hydrology = simRoot:FindFirstChild("Hydrology")
    if hydrology and hydrology:GetAttribute("DroughtPressure") == nil then table.insert(failures, "hydrology") end
    local situation = simRoot:FindFirstChild("Situation")
    if situation and situation:GetAttribute("Situation") == nil then table.insert(failures, "situation") end
    local intentQueue = simRoot:FindFirstChild("IntentQueue")
    if intentQueue and intentQueue:GetAttribute("IntentCount") == nil then table.insert(failures, "intent_queue") end
    local hygiene = simRoot:FindFirstChild("DataHygiene")
    if hygiene and hygiene:GetAttribute("Status") == nil then table.insert(failures, "data_hygiene") end
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

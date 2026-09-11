local WorldSimVerifier = {}

local REQUIRED_FOLDERS = {
    "Market", "Labor", "Ecology", "Threats", "Settlement", "Relationships",
    "Territory", "Routes", "Organization", "Population", "Migration", "Governance",
    "Recruitment", "Zones", "Hydrology", "Climate", "Terrain", "Disease", "RouteSecurity",
    "Situation", "IntentQueue", "DataHygiene", "Metrics", "Replay",
}

local REQUIRED_AGENT_ATTRS = {
    "Trait_Bravery", "Trait_Greed", "Trait_Loyalty", "Trait_Ambition", "Trait_RiskTolerance", "Trait_Discipline",
    "DominantMotive", "InjurySeverity", "WorldMod_Work", "SimulationLOD", "OrganizationId", "LaborBestProfession",
    "PsychologicalFear", "Morale", "MigrationPressure", "WorldZone", "WaterAccess", "WorldIntentOrder",
    "TerrainType", "DiseaseState", "DiseaseExposure",
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

    local checks = {
        { "Market", "Price_Food", "market" },
        { "Labor", "HighestDemandProfession", "labor" },
        { "Ecology", "ActiveResourceTotal", "ecology" },
        { "Threats", "ThreatPressure", "threats" },
        { "Settlement", "Stability", "settlement" },
        { "Population", "Total", "population" },
        { "Migration", "AveragePressure", "migration" },
        { "Governance", "Legitimacy", "governance" },
        { "Recruitment", "HighestNeedRole", "recruitment" },
        { "Zones", "SafeAgentCount", "zones" },
        { "Hydrology", "DroughtPressure", "hydrology" },
        { "Climate", "Season", "climate" },
        { "Terrain", "DominantTerrain", "terrain" },
        { "Disease", "OutbreakPressure", "disease" },
        { "RouteSecurity", "SecurityPressure", "route_security" },
        { "Situation", "Situation", "situation" },
        { "IntentQueue", "IntentCount", "intent_queue" },
        { "DataHygiene", "Status", "data_hygiene" },
    }

    for _, check in ipairs(checks) do
        local folder = simRoot:FindFirstChild(check[1])
        if folder and folder:GetAttribute(check[2]) == nil then table.insert(failures, check[3]) end
    end

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

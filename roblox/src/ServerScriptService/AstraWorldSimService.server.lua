local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)
local Traits = require(Astra.WorldSimTraits)
local Skills = require(Astra.WorldSimSkills)
local Motives = require(Astra.WorldSimMotives)
local Relationships = require(Astra.WorldSimRelationships)
local Injury = require(Astra.WorldSimInjury)
local Modifiers = require(Astra.WorldSimModifiers)
local Economy = require(Astra.WorldSimEconomy)
local LaborMarket = require(Astra.WorldSimLaborMarket)
local Ecology = require(Astra.WorldSimEcology)
local Threats = require(Astra.WorldSimThreats)
local Settlement = require(Astra.WorldSimSettlement)
local Territory = require(Astra.WorldSimTerritory)
local Routes = require(Astra.WorldSimRoutes)
local Organization = require(Astra.WorldSimOrganization)
local LOD = require(Astra.WorldSimLOD)
local Population = require(Astra.WorldSimPopulation)
local Psychology = require(Astra.WorldSimPsychology)
local Migration = require(Astra.WorldSimMigration)
local Governance = require(Astra.WorldSimGovernance)
local Recruitment = require(Astra.WorldSimRecruitment)
local Zones = require(Astra.WorldSimZones)
local Hydrology = require(Astra.WorldSimHydrology)
local Situation = require(Astra.WorldSimSituation)
local IntentQueue = require(Astra.WorldSimIntentQueue)
local Snapshot = require(Astra.WorldSimSnapshot)
local Serialization = require(Astra.WorldSimSerialization)
local Replay = require(Astra.WorldSimReplay)
local Metrics = require(Astra.WorldSimMetrics)
local DataHygiene = require(Astra.WorldSimDataHygiene)
local PersonalHistory = require(Astra.WorldSimPersonalHistory)
local Verifier = require(Astra.WorldSimVerifier)

local folders = WorldState.Ensure(Config)

local function ensureFolder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then return existing end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local simRoot = ensureFolder(workspace, "AstraWorldSim")
local marketFolder = ensureFolder(simRoot, "Market")
local laborFolder = ensureFolder(simRoot, "Labor")
local ecologyFolder = ensureFolder(simRoot, "Ecology")
local threatsFolder = ensureFolder(simRoot, "Threats")
local settlementFolder = ensureFolder(simRoot, "Settlement")
local relationsFolder = ensureFolder(simRoot, "Relationships")
local territoryFolder = ensureFolder(simRoot, "Territory")
local routesFolder = ensureFolder(simRoot, "Routes")
local organizationFolder = ensureFolder(simRoot, "Organization")
local populationFolder = ensureFolder(simRoot, "Population")
local migrationFolder = ensureFolder(simRoot, "Migration")
local governanceFolder = ensureFolder(simRoot, "Governance")
local recruitmentFolder = ensureFolder(simRoot, "Recruitment")
local zonesFolder = ensureFolder(simRoot, "Zones")
local hydrologyFolder = ensureFolder(simRoot, "Hydrology")
local situationFolder = ensureFolder(simRoot, "Situation")
local intentQueueFolder = ensureFolder(simRoot, "IntentQueue")
local hygieneFolder = ensureFolder(simRoot, "DataHygiene")
local metricsFolder = ensureFolder(simRoot, "Metrics")
local replayFolder = ensureFolder(simRoot, "Replay")

if simRoot:GetAttribute("Seed") == nil then simRoot:SetAttribute("Seed", 20904) end
simRoot:SetAttribute("Version", "WorldSimCorePack-0.4")
simRoot:SetAttribute("Authority", "observer-of-authoritative-world-tick")
simRoot:SetAttribute("OwnsWorldTick", false)
Metrics.Ensure(metricsFolder)

local seed = simRoot:GetAttribute("Seed")
local lastProcessedTick = -1

local function sortedAgents()
    local agents = {}
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then table.insert(agents, agent) end
    end
    table.sort(agents, function(a, b) return a.Name < b.Name end)
    return agents
end

local function initializeAgent(agent)
    if not agent:IsA("Model") then return end
    Traits.Ensure(agent, seed)
    Skills.Ensure(agent)
    Injury.Ensure(agent)
    agent:SetAttribute("WorldSimAttached", true)
end

for _, agent in ipairs(sortedAgents()) do initializeAgent(agent) end
folders.agents.ChildAdded:Connect(function(agent)
    task.defer(function() initializeAgent(agent) end)
end)

local function processTick(tick)
    if tick <= lastProcessedTick then return end
    lastProcessedTick = tick

    Metrics.Increment(metricsFolder, "TotalTicks", 1)
    local skillUps, injuryEvents, criticalTransitions = 0, 0, 0

    for _, agent in ipairs(sortedAgents()) do
        initializeAgent(agent)
        local skillUp = Skills.Tick(agent)
        if skillUp then
            skillUps += 1
            PersonalHistory.Record(agent, tick, "skill_up", string.format("%s reached level %d", skillUp.skill, skillUp.level), 0.7)
        end

        Motives.Update(agent)
        local injuryEvent = Injury.Tick(agent, folders.state, tick, seed)
        if injuryEvent then
            injuryEvents += 1
            PersonalHistory.Record(agent, tick, "injury", string.format("%s from %s", injuryEvent.injuryType, injuryEvent.cause), 0.9)
        end
        Modifiers.Update(agent, folders.state)
        criticalTransitions += PersonalHistory.Observe(agent, tick)
    end

    local relationInteractions = Relationships.Tick(folders.agents, tick, relationsFolder)
    local economy = Economy.Update(folders, marketFolder)
    local labor = LaborMarket.Update(folders.agents, marketFolder, laborFolder)
    local ecology = Ecology.Update(folders.resources, marketFolder, ecologyFolder, 32)
    local threats = Threats.Update(folders.agents, folders.state, threatsFolder, 32)
    local settlement = Settlement.Update(folders, settlementFolder, marketFolder)
    Territory.Update(folders, territoryFolder, 32, Config.StoragePosition or Vector3.new(0, 0, 0))
    Routes.Update(folders, routesFolder, Config.StoragePosition or Vector3.new(0, 0, 0))
    Organization.Update(folders, organizationFolder, settlementFolder)
    LOD.UpdateAll(folders.agents, metricsFolder)
    local population = Population.Update(folders.agents, populationFolder, 32)
    local hydrology = Hydrology.Update(folders.resources, folders.agents, folders.state, hydrologyFolder, 32)
    local zones = Zones.Update(folders.agents, territoryFolder, threatsFolder, zonesFolder, 32)

    local fearTotal, stressTotal, moraleTotal, psychologyCount = 0, 0, 0, 0
    for _, agent in ipairs(sortedAgents()) do
        local psychology = Psychology.Update(agent, threatsFolder, settlementFolder)
        fearTotal += psychology.fear
        stressTotal += psychology.stress
        moraleTotal += psychology.morale
        psychologyCount += 1
    end
    local psychDivisor = math.max(1, psychologyCount)
    local migration = Migration.Update(folders.agents, marketFolder, settlementFolder, threatsFolder, territoryFolder, 32)
    local governance = Governance.Update(settlementFolder, organizationFolder, threatsFolder, governanceFolder)
    local recruitment = Recruitment.Update(populationFolder, settlementFolder, threatsFolder, laborFolder, recruitmentFolder)
    local situation = Situation.Update(settlementFolder, threatsFolder, ecologyFolder, laborFolder, governanceFolder, situationFolder)
    local intents = IntentQueue.Capture(folders.agents, tick, intentQueueFolder)

    migrationFolder:SetAttribute("AveragePressure", math.floor((migration.averagePressure or 0) * 1000 + 0.5) / 10)
    migrationFolder:SetAttribute("CandidateCount", migration.candidateCount or 0)

    local snapshot = Snapshot.Capture(folders, 32)
    local serialized = Serialization.Serialize(snapshot)
    local changed = Replay.Record(snapshot, replayFolder)
    Metrics.RecordSnapshot(metricsFolder, changed)
    DataHygiene.Update(folders, simRoot, hygieneFolder)

    if skillUps > 0 then Metrics.Increment(metricsFolder, "SkillUps", skillUps) end
    if injuryEvents > 0 then Metrics.Increment(metricsFolder, "InjuryEvents", injuryEvents) end
    if relationInteractions > 0 then Metrics.Increment(metricsFolder, "RelationshipInteractions", relationInteractions) end
    if criticalTransitions > 0 then Metrics.Increment(metricsFolder, "CriticalTransitions", criticalTransitions) end

    Metrics.Gauge(metricsFolder, "MarketTradeHealth", math.floor(economy.tradeHealth * 10 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "MarketAverageScarcity", math.floor(economy.averageScarcity * 1000 + 0.5) / 1000)
    Metrics.Gauge(metricsFolder, "LaborHighestWagePremium", math.floor((labor.premium or 1) * 1000 + 0.5) / 1000)
    Metrics.Gauge(metricsFolder, "EcologyActiveResources", ecology.activeTotal or 0)
    Metrics.Gauge(metricsFolder, "ThreatPressure", math.floor((threats.pressure or 0) * 1000 + 0.5) / 1000)
    Metrics.Gauge(metricsFolder, "PopulationTotal", population.total or 0)
    Metrics.Gauge(metricsFolder, "SettlementStability", settlement.Stability)
    Metrics.Gauge(metricsFolder, "SettlementProsperity", settlement.Prosperity)
    Metrics.Gauge(metricsFolder, "AverageFear", math.floor((fearTotal / psychDivisor) * 1000 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "AverageStress", math.floor((stressTotal / psychDivisor) * 1000 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "AverageMorale", math.floor((moraleTotal / psychDivisor) * 1000 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "MigrationCandidateCount", migration.candidateCount or 0)
    Metrics.Gauge(metricsFolder, "GovernanceLegitimacy", math.floor((governance.legitimacy or 0) * 1000 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "RecruitmentUrgency", math.floor((recruitment.urgency or 0) * 1000 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "DroughtPressure", math.floor((hydrology.droughtPressure or 0) * 1000 + 0.5) / 10)
    Metrics.Gauge(metricsFolder, "SafeAgents", zones.safe or 0)
    Metrics.Gauge(metricsFolder, "SituationPriority", situation.priority or 0)
    Metrics.Gauge(metricsFolder, "IntentCount", #intents)
    Metrics.Gauge(metricsFolder, "SerializedSnapshotBytes", #serialized)

    simRoot:SetAttribute("LastProcessedTick", tick)
    simRoot:SetAttribute("LastFingerprint", snapshot.fingerprint)
    simRoot:SetAttribute("LastSerializedBytes", #serialized)
    simRoot:SetAttribute("LastAgentCount", #snapshot.agents)
    simRoot:SetAttribute("LastResourceCount", #snapshot.resources)
    simRoot:SetAttribute("LastStructureCount", #snapshot.structures)
    simRoot:SetAttribute("Status", "ONLINE")

    folders.state:SetAttribute("WorldSimStatus", "ONLINE")
    folders.state:SetAttribute("WorldSimFingerprint", snapshot.fingerprint)
    Verifier.Update(folders, simRoot)
end

local function scheduleCurrentTick()
    local tick = folders.state:GetAttribute("WorldTick") or 0
    task.defer(function()
        local ok, err = pcall(processTick, tick)
        if not ok then
            simRoot:SetAttribute("Status", "ERROR")
            simRoot:SetAttribute("LastError", tostring(err))
            folders.state:SetAttribute("WorldSimCoreStatus", "ERROR")
            warn("[AstraWorldSim]", err)
        else
            simRoot:SetAttribute("LastError", "")
        end
    end)
end

folders.state:GetAttributeChangedSignal("WorldTick"):Connect(scheduleCurrentTick)

if (folders.state:GetAttribute("WorldTick") or 0) > 0 then scheduleCurrentTick() end

print("[AstraLife] WorldSim Core Pack attached passively to authoritative WorldTick")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K7Migration = Kingdom:WaitForChild("K7Migration")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local MigrationPressure = require(K7Migration.MigrationPressure)
local K7Verifier = require(K7Migration.K7Verifier)

local scope = StateWriter.Scope("K7Migration")
scope:SetAttribute("Module", "KingdomK7Migration")
scope:SetAttribute("Authority", "aggregate-advisory-only")
scope:SetAttribute("CanMoveAgents", false)
scope:SetAttribute("CadenceSource", "AgentWorldTick")

local lastTick = -1
local revision = 0
local lastSignature = nil

local function snapshotAgents()
    local result = {}
    local agents = SourceReader.Agents()
    if not agents then return result end

    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then
            local root = agent:FindFirstChild("HumanoidRootPart")
            local humanoid = agent:FindFirstChildOfClass("Humanoid")
            local position = root and string.format("%.4f,%.4f,%.4f", root.Position.X, root.Position.Y, root.Position.Z) or "nil"
            result[agent.Name] = table.concat({
                position,
                tostring(agent:GetAttribute("Role")),
                tostring(agent:GetAttribute("Hunger")),
                tostring(agent:GetAttribute("Thirst")),
                tostring(agent:GetAttribute("Energy")),
                tostring(agent:GetAttribute("Safety")),
                tostring(agent:GetAttribute("Social")),
                tostring(agent:GetAttribute("SurvivalCritical")),
                tostring(humanoid and humanoid.Health or "nil"),
            }, "|")
        end
    end
    return result
end

local function signature(result)
    return table.concat({
        result.state,
        tostring(result.observedPopulation),
        tostring(result.candidateCount),
        tostring(result.highRiskCount),
        tostring(result.averagePressurePct),
        tostring(result.maxPressurePct),
        tostring(result.attractionPct),
        tostring(result.counts.STAY),
        tostring(result.counts.CONSIDER),
        tostring(result.counts.REFUGE),
        tostring(result.counts.LEAVE),
    }, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local agentsBefore = snapshotAgents()
    local source = SourceReader.Snapshot()
    local result = MigrationPressure.Compute(source, SourceReader.Agents())

    local nextSignature = signature(result)
    if nextSignature ~= lastSignature then
        revision += 1
        lastSignature = nextSignature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        State = result.state,
        ObservedPopulation = result.observedPopulation,
        CandidateCount = result.candidateCount,
        HighRiskCount = result.highRiskCount,
        StayCount = result.counts.STAY,
        ConsiderCount = result.counts.CONSIDER,
        RefugeCount = result.counts.REFUGE,
        LeaveCount = result.counts.LEAVE,
        AveragePressurePct = result.averagePressurePct,
        MaxPressurePct = result.maxPressurePct,
        AttractionPct = result.attractionPct,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
    })

    local stocksAfter = SourceReader.ReadStocks()
    local agentsAfter = snapshotAgents()
    K7Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
end

local agentState = SourceReader.AgentState()
if agentState then
    lastTick = agentState:GetAttribute("WorldTick") or 0
    agentState:GetAttributeChangedSignal("WorldTick"):Connect(function()
        local tick = agentState:GetAttribute("WorldTick") or 0
        if tick ~= lastTick then
            lastTick = tick
            publish()
        end
    end)
end

publish()
print("[AstraLife] Kingdom K7 Migration online: aggregate pressure only, no movement authority")

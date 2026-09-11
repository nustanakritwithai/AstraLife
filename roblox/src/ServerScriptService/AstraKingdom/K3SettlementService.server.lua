local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K3Settlement = Kingdom:WaitForChild("K3Settlement")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local SettlementState = require(K3Settlement.SettlementState)
local K3Verifier = require(K3Settlement.K3Verifier)

local scope = StateWriter.Scope("K3Settlement")
scope:SetAttribute("Module", "KingdomK3Settlement")
scope:SetAttribute("Authority", "projection-only")
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
            local humanoid = agent:FindFirstChildOfClass("Humanoid")
            result[agent.Name] = table.concat({
                tostring(agent:GetAttribute("Role")),
                tostring(agent:GetAttribute("Hunger")),
                tostring(agent:GetAttribute("Thirst")),
                tostring(agent:GetAttribute("Energy")),
                tostring(agent:GetAttribute("Safety")),
                tostring(agent:GetAttribute("Social")),
                tostring(humanoid and humanoid.Health or "nil"),
            }, "|")
        end
    end
    return result
end

local function signature(result)
    return table.concat({
        result.state,
        tostring(result.population),
        tostring(result.criticalPopulation),
        tostring(result.foodSecurity),
        tostring(result.waterSecurity),
        tostring(result.prosperity),
        tostring(result.stability),
        tostring(result.unrest),
        tostring(result.resilience),
    }, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local agentsBefore = snapshotAgents()
    local source = SourceReader.Snapshot()
    local result = SettlementState.Compute(source)

    local nextSignature = signature(result)
    if nextSignature ~= lastSignature then
        revision += 1
        lastSignature = nextSignature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        State = result.state,
        Population = result.population,
        CriticalPopulation = result.criticalPopulation,
        FoodSecurity = result.foodSecurity,
        WaterSecurity = result.waterSecurity,
        StorageHealth = result.storageHealth,
        Infrastructure = result.infrastructure,
        AverageSafety = result.averageSafety,
        AverageSocial = result.averageSocial,
        AverageHealth = result.averageHealth,
        Danger = result.danger,
        Prosperity = result.prosperity,
        Stability = result.stability,
        Unrest = result.unrest,
        Resilience = result.resilience,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
    })

    local stocksAfter = SourceReader.ReadStocks()
    local agentsAfter = snapshotAgents()
    K3Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
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
print("[AstraLife] Kingdom K3 Settlement online: society health projection only")

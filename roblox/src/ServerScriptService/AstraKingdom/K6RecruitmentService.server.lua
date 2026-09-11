local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K6Recruitment = Kingdom:WaitForChild("K6Recruitment")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local RecruitmentDemand = require(K6Recruitment.RecruitmentDemand)
local K6Verifier = require(K6Recruitment.K6Verifier)

local scope = StateWriter.Scope("K6Recruitment")
scope:SetAttribute("Module", "KingdomK6Recruitment")
scope:SetAttribute("Authority", "advisory-only")
scope:SetAttribute("CanSpawnAgents", false)
scope:SetAttribute("CanChangeRoles", false)
scope:SetAttribute("CadenceSource", "AgentWorldTick")

local lastTick = -1
local revision = 0
local lastSignature = nil

local function snapshotAgents()
    local result = {}
    local agents = SourceReader.Agents()
    if not agents then return result end
    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then result[agent.Name] = tostring(agent:GetAttribute("Role")) end
    end
    return result
end

local function signature(result)
    local parts = {
        result.highestNeedRole,
        tostring(result.highestNeedCount),
        tostring(result.totalNeed),
        tostring(result.urgencyPct),
    }
    for _, role in ipairs(RecruitmentDemand.RoleOrder()) do
        local row = result.needs[role]
        table.insert(parts, role .. ":" .. row.current .. ":" .. row.target .. ":" .. row.need)
    end
    return table.concat(parts, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local agentsBefore = snapshotAgents()
    local source = SourceReader.Snapshot()
    local result = RecruitmentDemand.Compute(source, SourceReader.Agents())

    for _, role in ipairs(RecruitmentDemand.RoleOrder()) do
        local row = result.needs[role]
        StateWriter.SetMany(scope, {
            ["Current_" .. role] = row.current,
            ["Target_" .. role] = row.target,
            ["ContextBonus_" .. role] = row.contextualBonus,
            ["Need_" .. role] = row.need,
        })
    end

    local nextSignature = signature(result)
    if nextSignature ~= lastSignature then
        revision += 1
        lastSignature = nextSignature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        Population = result.population,
        HighestNeedRole = result.highestNeedRole,
        HighestNeedCount = result.highestNeedCount,
        TotalNeed = result.totalNeed,
        UrgencyPct = result.urgencyPct,
        SuggestedOffer = result.suggestedOffer,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
    })

    local stocksAfter = SourceReader.ReadStocks()
    local agentsAfter = snapshotAgents()
    K6Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
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
print("[AstraLife] Kingdom K6 Recruitment online: demand recommendations only")

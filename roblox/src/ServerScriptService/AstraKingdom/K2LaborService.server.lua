local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K2Labor = Kingdom:WaitForChild("K2Labor")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local LaborMarket = require(K2Labor.LaborMarket)
local K2Verifier = require(K2Labor.K2Verifier)

local scope = StateWriter.Scope("K2Labor")
scope:SetAttribute("Module", "KingdomK2Labor")
scope:SetAttribute("Authority", "advisory-only")
scope:SetAttribute("CadenceSource", "AgentWorldTick")

local lastTick = -1
local revision = 0
local lastSignature = nil

local function snapshotRoles()
    local roles = {}
    local agents = SourceReader.Agents()
    if not agents then return roles end
    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then
            roles[agent.Name] = agent:GetAttribute("Role")
        end
    end
    return roles
end

local function previousPremiums()
    local out = {}
    for _, profession in ipairs(LaborMarket.ProfessionOrder()) do
        local value = scope:GetAttribute("WagePremium_" .. profession)
        if type(value) == "number" then out[profession] = value end
    end
    return out
end

local function resultSignature(result)
    local parts = {
        result.highestDemandProfession,
        tostring(result.highestPressure),
        tostring(result.averagePressure),
    }
    for _, profession in ipairs(LaborMarket.ProfessionOrder()) do
        local row = result.professions[profession]
        table.insert(parts, profession .. ":" .. tostring(row.pressure) .. ":" .. tostring(row.wagePremium))
    end
    return table.concat(parts, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local rolesBefore = snapshotRoles()
    local source = SourceReader.Snapshot()
    local result = LaborMarket.Compute(source, previousPremiums())

    for _, profession in ipairs(LaborMarket.ProfessionOrder()) do
        local row = result.professions[profession]
        StateWriter.SetMany(scope, {
            ["Pressure_" .. profession] = row.pressure,
            ["UnitsPerCapita_" .. profession] = row.unitsPerCapita,
            ["TargetPremium_" .. profession] = row.targetPremium,
            ["WagePremium_" .. profession] = row.wagePremium,
        })
    end

    local signature = resultSignature(result)
    if signature ~= lastSignature then
        revision += 1
        lastSignature = signature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        HighestDemandProfession = result.highestDemandProfession,
        HighestPressure = result.highestPressure,
        HighestWagePremium = result.highestWagePremium,
        AveragePressure = result.averagePressure,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
        ObservedPopulation = source.population.total,
    })

    local stocksAfter = SourceReader.ReadStocks()
    local rolesAfter = snapshotRoles()
    K2Verifier.Run(scope, result, stocksBefore, stocksAfter, rolesBefore, rolesAfter)
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
print("[AstraLife] Kingdom K2 Labor online: wage pressure advisory only")

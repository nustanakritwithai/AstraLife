local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K1Market = Kingdom:WaitForChild("K1Market")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local MarketEconomy = require(K1Market.MarketEconomy)
local K1Verifier = require(K1Market.K1Verifier)

local scope = StateWriter.Scope("K1Market")
scope:SetAttribute("Module", "KingdomK1Market")
scope:SetAttribute("Authority", "projection-only")
scope:SetAttribute("CadenceSource", "AgentWorldTick")

local lastTick = -1
local revision = 0
local lastSignature = nil

local function previousPrices()
    local out = {}
    for _, resourceType in ipairs(MarketEconomy.ResourceOrder()) do
        local value = scope:GetAttribute("Price_" .. resourceType)
        if type(value) == "number" then out[resourceType] = value end
    end
    return out
end

local function signature(result)
    local parts = {
        result.regime,
        tostring(result.averageScarcity),
        tostring(result.averageVolatility),
        tostring(result.tradeHealth),
        tostring(result.stressIndex),
    }
    for _, resourceType in ipairs(MarketEconomy.ResourceOrder()) do
        local row = result.resources[resourceType]
        table.insert(parts, resourceType .. ":" .. tostring(row.price) .. ":" .. tostring(row.scarcity))
    end
    return table.concat(parts, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local source = SourceReader.Snapshot()
    local result = MarketEconomy.Compute(source, previousPrices())

    for _, resourceType in ipairs(MarketEconomy.ResourceOrder()) do
        local row = result.resources[resourceType]
        StateWriter.SetMany(scope, {
            ["ObservedStock_" .. resourceType] = row.stock,
            ["Demand_" .. resourceType] = row.demand,
            ["Scarcity_" .. resourceType] = row.scarcity,
            ["Coverage_" .. resourceType] = row.coverage,
            ["RawPrice_" .. resourceType] = row.rawPrice,
            ["Price_" .. resourceType] = row.price,
            ["Volatility_" .. resourceType] = row.volatility,
            ["Shortage_" .. resourceType] = row.shortage,
            ["Critical_" .. resourceType] = row.critical,
        })
    end

    local nextSignature = signature(result)
    if nextSignature ~= lastSignature then
        revision += 1
        lastSignature = nextSignature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        AverageScarcity = result.averageScarcity,
        AverageVolatility = result.averageVolatility,
        TradeHealth = result.tradeHealth,
        StressIndex = result.stressIndex,
        Regime = result.regime,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
        ObservedPopulation = source.population.total,
        ObservedCriticalPopulation = source.population.critical,
        ObservedDangerActive = source.signals.dangerActive,
    })

    local stocksAfter = SourceReader.ReadStocks()
    K1Verifier.Run(scope, source, result, stocksBefore, stocksAfter)
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
print("[AstraLife] Kingdom K1 Market online: deterministic read-only economy projection")

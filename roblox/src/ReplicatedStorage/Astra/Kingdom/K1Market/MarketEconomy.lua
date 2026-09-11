local Config = require(script.Parent.Config)

local MarketEconomy = {}

local RESOURCE_ORDER = { "Food", "Water", "Wood", "Stone" }

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function round(value, places)
    local factor = 10 ^ (places or 3)
    return math.floor(value * factor + 0.5) / factor
end

local function classifyRegime(averageScarcity, tradeHealth)
    if averageScarcity >= 3.0 or tradeHealth <= 25 then return "CRISIS" end
    if averageScarcity >= 1.6 or tradeHealth <= 50 then return "TIGHT" end
    if averageScarcity <= 0.65 and tradeHealth >= 75 then return "SURPLUS" end
    return "BALANCED"
end

local function demandFor(resourceType, source)
    local definition = Config.Resources[resourceType]
    local population = source.population.total or 0
    local critical = source.population.critical or 0
    local structures = source.structureCount or 0

    local demand = population * definition.perCapitaDemand
        + critical * definition.criticalDemand
        + structures * definition.infrastructureDemand

    return math.max(1, demand)
end

function MarketEconomy.Compute(source, previousPrices)
    previousPrices = previousPrices or {}

    local dangerMultiplier = source.signals.dangerActive and 1.35 or 1.0
    local population = source.population.total or 0
    local crowding = clamp(population / 8, 0, 2)

    local result = {
        schemaVersion = Config.SchemaVersion,
        resources = {},
        averageScarcity = 0,
        averageVolatility = 0,
        tradeHealth = 100,
        stressIndex = 0,
        regime = "BALANCED",
    }

    local scarcitySum = 0
    local volatilitySum = 0
    local criticalCount = 0

    for _, resourceType in ipairs(RESOURCE_ORDER) do
        local definition = Config.Resources[resourceType]
        local stock = source.stocks[resourceType] or 0
        local demand = demandFor(resourceType, source)
        local scarcity = clamp(demand / math.max(stock, 1), Config.MinScarcity, Config.MaxScarcity)

        local crowdMultiplier = 1.0
        if resourceType == "Food" then
            crowdMultiplier = 1 + math.max(0, crowding - 0.9) * 0.45
        elseif resourceType == "Water" then
            crowdMultiplier = 1 + math.max(0, crowding - 1.0) * 0.30
        end

        local rawPrice = definition.basePrice * (scarcity ^ 0.75) * dangerMultiplier * crowdMultiplier
        rawPrice = clamp(
            rawPrice,
            definition.basePrice * Config.MinPriceMultiplier,
            definition.basePrice * Config.MaxPriceMultiplier
        )

        local previous = previousPrices[resourceType]
        local price = previous and (
            previous * (1 - Config.PriceSmoothingAlpha)
            + rawPrice * Config.PriceSmoothingAlpha
        ) or rawPrice

        local volatility = previous and math.abs(price - previous) / math.max(previous, 0.01) or 0
        local coverage = stock / math.max(demand, 0.01)
        local shortage = scarcity > 1.0
        local critical = scarcity >= 3.0
        if critical then criticalCount += 1 end

        result.resources[resourceType] = {
            stock = round(stock, 2),
            demand = round(demand, 2),
            scarcity = round(scarcity, 3),
            coverage = round(coverage, 3),
            basePrice = definition.basePrice,
            rawPrice = round(rawPrice, 3),
            price = round(price, 3),
            volatility = round(volatility, 4),
            shortage = shortage,
            critical = critical,
        }

        scarcitySum += scarcity
        volatilitySum += volatility
    end

    result.averageScarcity = scarcitySum / #RESOURCE_ORDER
    result.averageVolatility = volatilitySum / #RESOURCE_ORDER

    local stockCapacity = math.max(source.stocks.Capacity or 0, 1)
    local storageHealth = clamp((source.stocks.Total or 0) / stockCapacity, 0, 1)
    local criticalRatio = (source.population.critical or 0) / math.max(population, 1)
    local scarcityPenalty = math.max(0, result.averageScarcity - 1) * 18
    local dangerPenalty = source.signals.dangerActive and 18 or 0
    local volatilityPenalty = math.min(25, result.averageVolatility * 120)
    local survivalPenalty = criticalRatio * 30

    result.tradeHealth = clamp(
        100 + storageHealth * 12 - scarcityPenalty - dangerPenalty - volatilityPenalty - survivalPenalty,
        0,
        100
    )
    result.stressIndex = clamp(
        (result.averageScarcity - 1) * 0.30
            + result.averageVolatility * 0.80
            + criticalRatio * 0.35
            + (source.signals.dangerActive and 0.20 or 0)
            + criticalCount * 0.08,
        0,
        1
    )
    result.regime = classifyRegime(result.averageScarcity, result.tradeHealth)

    result.averageScarcity = round(result.averageScarcity, 3)
    result.averageVolatility = round(result.averageVolatility, 4)
    result.tradeHealth = round(result.tradeHealth, 1)
    result.stressIndex = round(result.stressIndex, 3)

    return result
end

function MarketEconomy.ResourceOrder()
    return table.clone(RESOURCE_ORDER)
end

return MarketEconomy

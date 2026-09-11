local Config = require(script.Parent.Config)

local SettlementState = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function round(value, places)
    local factor = 10 ^ (places or 3)
    return math.floor(value * factor + 0.5) / factor
end

local function classify(values)
    if values.foodSecurity < 30 or values.waterSecurity < 30 or values.unrest >= 70 then
        return "CRISIS"
    end
    if values.stability < 45 or values.resilience < 45 then
        return "FRAGILE"
    end
    if values.prosperity >= 75 and values.stability >= 70 then
        return "PROSPEROUS"
    end
    return "STABLE"
end

function SettlementState.Compute(source)
    local population = source.population.total or 0
    local divisor = math.max(1, population)
    local criticalRatio = (source.population.critical or 0) / divisor
    local safety = clamp((source.population.averageSafety or 100) / 100, 0, 1)
    local social = clamp((source.population.averageSocial or 100) / 100, 0, 1)
    local health = clamp(source.population.averageHealthRatio or 1, 0, 1)

    local foodTarget = math.max(1, population * Config.FoodReservePerCapita)
    local waterTarget = math.max(1, population * Config.WaterReservePerCapita)
    local foodSecurity01 = clamp((source.stocks.Food or 0) / foodTarget, 0, 1)
    local waterSecurity01 = clamp((source.stocks.Water or 0) / waterTarget, 0, 1)
    local storageHealth = clamp((source.stocks.Total or 0) / math.max(source.stocks.Capacity or 0, 1), 0, 1)
    local infrastructure = clamp((source.structureCount or 0) / Config.TargetStructureCount, 0, 1)

    local danger = clamp(
        (source.signals.dangerActive and 0.50 or 0)
            + criticalRatio * 0.30
            + (1 - safety) * 0.30,
        0,
        1
    )

    local prosperity = clamp(
        storageHealth * 0.25
            + foodSecurity01 * 0.20
            + waterSecurity01 * 0.15
            + infrastructure * 0.20
            + health * 0.20
            - danger * 0.15,
        0,
        1
    )

    local stability = clamp(
        safety * 0.25
            + social * 0.15
            + health * 0.20
            + prosperity * 0.25
            + foodSecurity01 * 0.075
            + waterSecurity01 * 0.075
            - danger * 0.35,
        0,
        1
    )

    local unrest = clamp(
        (1 - stability) * 0.50
            + criticalRatio * 0.25
            + (1 - foodSecurity01) * 0.15
            + (1 - waterSecurity01) * 0.10,
        0,
        1
    )

    local resilience = clamp(
        foodSecurity01 * 0.20
            + waterSecurity01 * 0.20
            + health * 0.20
            + safety * 0.15
            + social * 0.10
            + infrastructure * 0.15,
        0,
        1
    )

    local values = {
        schemaVersion = Config.SchemaVersion,
        population = population,
        criticalPopulation = source.population.critical or 0,
        foodSecurity = round(foodSecurity01 * 100, 1),
        waterSecurity = round(waterSecurity01 * 100, 1),
        storageHealth = round(storageHealth * 100, 1),
        infrastructure = round(infrastructure * 100, 1),
        averageSafety = round(safety * 100, 1),
        averageSocial = round(social * 100, 1),
        averageHealth = round(health * 100, 1),
        danger = round(danger * 100, 1),
        prosperity = round(prosperity * 100, 1),
        stability = round(stability * 100, 1),
        unrest = round(unrest * 100, 1),
        resilience = round(resilience * 100, 1),
    }
    values.state = classify(values)
    return values
end

return SettlementState

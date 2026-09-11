local Config = require(script.Parent.Config)

local LaborMarket = {}

local PROFESSION_ORDER = { "farmer", "woodcutter", "miner", "crafter" }

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function round(value, places)
    local factor = 10 ^ (places or 3)
    return math.floor(value * factor + 0.5) / factor
end

local function pressureFor(definition, source)
    local population = math.max(1, source.population.total or 0)
    local stock = source.stocks[definition.resource] or 0
    local perCapita = stock / population
    local primaryPressure = clamp(1 - perCapita / definition.healthyPerCapita, 0, 1)

    local secondaryPressure = 0
    if definition.secondaryResource then
        local secondaryStock = source.stocks[definition.secondaryResource] or 0
        secondaryPressure = clamp(1 - (secondaryStock / population) / definition.healthyPerCapita, 0, 1)
    end

    local criticalRatio = (source.population.critical or 0) / population
    local dangerPressure = source.signals.dangerActive and 0.15 or 0
    local infrastructurePressure = math.max(0, 4 - (source.structureCount or 0)) / 4

    local pressure = primaryPressure * definition.baseDemandWeight
        + secondaryPressure * 0.25
        + criticalRatio * 0.30
        + dangerPressure

    if definition == Config.Professions.crafter then
        pressure += infrastructurePressure * 0.25
    end

    return clamp(pressure, 0, 1), perCapita
end

function LaborMarket.Compute(source, previousPremiums)
    previousPremiums = previousPremiums or {}
    local result = {
        schemaVersion = Config.SchemaVersion,
        professions = {},
        highestDemandProfession = "farmer",
        highestPressure = -1,
        highestWagePremium = Config.MinWagePremium,
        averagePressure = 0,
    }

    local pressureSum = 0

    for _, profession in ipairs(PROFESSION_ORDER) do
        local definition = Config.Professions[profession]
        local pressure, unitsPerCapita = pressureFor(definition, source)
        local targetPremium = clamp(
            Config.MinWagePremium + pressure * (Config.MaxWagePremium - Config.MinWagePremium),
            Config.MinWagePremium,
            Config.MaxWagePremium
        )
        local previous = previousPremiums[profession]
        local premium = previous and (
            previous * (1 - Config.SmoothingAlpha)
            + targetPremium * Config.SmoothingAlpha
        ) or targetPremium

        result.professions[profession] = {
            pressure = round(pressure, 3),
            unitsPerCapita = round(unitsPerCapita, 3),
            targetPremium = round(targetPremium, 3),
            wagePremium = round(premium, 3),
        }

        pressureSum += pressure
        if pressure > result.highestPressure
            or (pressure == result.highestPressure and profession < result.highestDemandProfession)
        then
            result.highestDemandProfession = profession
            result.highestPressure = pressure
            result.highestWagePremium = premium
        end
    end

    result.averagePressure = round(pressureSum / #PROFESSION_ORDER, 3)
    result.highestPressure = round(result.highestPressure, 3)
    result.highestWagePremium = round(result.highestWagePremium, 3)
    return result
end

function LaborMarket.ProfessionOrder()
    return table.clone(PROFESSION_ORDER)
end

return LaborMarket

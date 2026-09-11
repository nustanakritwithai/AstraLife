local MigrationPressure = {}

MigrationPressure.SchemaVersion = "K7.1"

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function round(value, places)
    local factor = 10 ^ (places or 2)
    return math.floor(value * factor + 0.5) / factor
end

local function sortedAgents(agentsFolder)
    local agents = {}
    if not agentsFolder then return agents end
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then table.insert(agents, agent) end
    end
    table.sort(agents, function(a, b) return a.Name < b.Name end)
    return agents
end

local function classifyPressure(pressure)
    if pressure >= 0.75 then return "LEAVE" end
    if pressure >= 0.50 then return "REFUGE" end
    if pressure >= 0.30 then return "CONSIDER" end
    return "STAY"
end

local function classifyWorld(averagePressure, highRiskRatio)
    if averagePressure >= 0.65 or highRiskRatio >= 0.35 then return "EXODUS_RISK" end
    if averagePressure >= 0.45 then return "PRESSURED" end
    if averagePressure >= 0.25 then return "BUILDING" end
    return "CALM"
end

function MigrationPressure.Compute(source, agentsFolder)
    local population = math.max(1, source.population.total or 0)
    local foodCoverage = clamp((source.stocks.Food or 0) / math.max(population * 3, 1), 0, 1)
    local waterCoverage = clamp((source.stocks.Water or 0) / math.max(population * 3, 1), 0, 1)
    local reserveHealth = clamp((source.stocks.Total or 0) / math.max(source.stocks.Capacity or 0, 1), 0, 1)
    local danger = source.signals.dangerActive and 1 or 0
    local globalResourcePressure = clamp((1 - foodCoverage) * 0.55 + (1 - waterCoverage) * 0.45, 0, 1)

    local counts = { STAY = 0, CONSIDER = 0, REFUGE = 0, LEAVE = 0 }
    local pressureSum = 0
    local maxPressure = 0
    local candidateCount = 0
    local highRiskCount = 0
    local observed = 0

    for _, agent in ipairs(sortedAgents(agentsFolder)) do
        local hunger = clamp((agent:GetAttribute("Hunger") or 100) / 100, 0, 1)
        local thirst = clamp((agent:GetAttribute("Thirst") or 100) / 100, 0, 1)
        local energy = clamp((agent:GetAttribute("Energy") or 100) / 100, 0, 1)
        local safety = clamp((agent:GetAttribute("Safety") or 100) / 100, 0, 1)
        local social = clamp((agent:GetAttribute("Social") or 100) / 100, 0, 1)
        local survivalNeed = 1 - math.min(hunger, thirst, energy)
        local critical = agent:GetAttribute("SurvivalCritical") == true and 1 or 0

        local pressure = clamp(
            globalResourcePressure * 0.30
                + survivalNeed * 0.35
                + (1 - safety) * 0.20
                + (1 - social) * 0.05
                + danger * 0.10
                + critical * 0.15,
            0,
            1
        )

        local intent = classifyPressure(pressure)
        counts[intent] += 1
        pressureSum += pressure
        maxPressure = math.max(maxPressure, pressure)
        observed += 1
        if pressure >= 0.50 then candidateCount += 1 end
        if pressure >= 0.75 then highRiskCount += 1 end
    end

    local divisor = math.max(1, observed)
    local averagePressure = pressureSum / divisor
    local highRiskRatio = highRiskCount / divisor
    local attraction = clamp(
        reserveHealth * 0.25
            + foodCoverage * 0.25
            + waterCoverage * 0.25
            + clamp((source.population.averageSafety or 100) / 100, 0, 1) * 0.15
            + clamp((source.population.averageSocial or 100) / 100, 0, 1) * 0.10,
        0,
        1
    )

    return {
        schemaVersion = MigrationPressure.SchemaVersion,
        observedPopulation = observed,
        counts = counts,
        candidateCount = candidateCount,
        highRiskCount = highRiskCount,
        averagePressurePct = round(averagePressure * 100, 1),
        maxPressurePct = round(maxPressure * 100, 1),
        attractionPct = round(attraction * 100, 1),
        state = classifyWorld(averagePressure, highRiskRatio),
    }
end

return MigrationPressure

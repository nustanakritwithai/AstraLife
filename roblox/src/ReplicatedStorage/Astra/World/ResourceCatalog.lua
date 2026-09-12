local ResourceCatalog = {}

ResourceCatalog.Definitions = {
    Ocean = {
        vegetationCapacity = 0.00,
        foodCapacity = 0.00,
        woodCapacity = 0.00,
        vegetationRate = 0.0000,
        foodRate = 0.0000,
        woodRate = 0.0000,
        preferredMoisture = 1.00,
        preferredTemperature = 0.55,
    },
    Shore = {
        vegetationCapacity = 0.25,
        foodCapacity = 2.0,
        woodCapacity = 1.0,
        vegetationRate = 0.0014,
        foodRate = 0.010,
        woodRate = 0.002,
        preferredMoisture = 0.58,
        preferredTemperature = 0.62,
    },
    Plains = {
        vegetationCapacity = 0.82,
        foodCapacity = 7.0,
        woodCapacity = 3.0,
        vegetationRate = 0.0026,
        foodRate = 0.030,
        woodRate = 0.004,
        preferredMoisture = 0.52,
        preferredTemperature = 0.60,
    },
    Forest = {
        vegetationCapacity = 1.00,
        foodCapacity = 8.0,
        woodCapacity = 14.0,
        vegetationRate = 0.0031,
        foodRate = 0.036,
        woodRate = 0.016,
        preferredMoisture = 0.62,
        preferredTemperature = 0.56,
    },
    Wetland = {
        vegetationCapacity = 0.92,
        foodCapacity = 9.0,
        woodCapacity = 7.0,
        vegetationRate = 0.0034,
        foodRate = 0.040,
        woodRate = 0.009,
        preferredMoisture = 0.82,
        preferredTemperature = 0.58,
    },
    Desert = {
        vegetationCapacity = 0.18,
        foodCapacity = 1.0,
        woodCapacity = 0.5,
        vegetationRate = 0.0007,
        foodRate = 0.004,
        woodRate = 0.001,
        preferredMoisture = 0.18,
        preferredTemperature = 0.72,
    },
    Highland = {
        vegetationCapacity = 0.36,
        foodCapacity = 2.5,
        woodCapacity = 2.0,
        vegetationRate = 0.0011,
        foodRate = 0.009,
        woodRate = 0.002,
        preferredMoisture = 0.45,
        preferredTemperature = 0.42,
    },
    Mountain = {
        vegetationCapacity = 0.08,
        foodCapacity = 0.4,
        woodCapacity = 0.4,
        vegetationRate = 0.0003,
        foodRate = 0.001,
        woodRate = 0.0003,
        preferredMoisture = 0.38,
        preferredTemperature = 0.28,
    },
}

local SEASON_MULTIPLIER = {
    Spring = 1.20,
    Summer = 1.00,
    Autumn = 0.72,
    Winter = 0.36,
}

function ResourceCatalog.Get(biomeName)
    return ResourceCatalog.Definitions[biomeName] or ResourceCatalog.Definitions.Plains
end

function ResourceCatalog.GetSeasonMultiplier(season)
    return SEASON_MULTIPLIER[season] or 1.0
end

function ResourceCatalog.Suitability(cell, climate)
    local definition = ResourceCatalog.Get(cell.biome)
    if (cell.biome or "") == "Ocean" then
        return 0
    end

    local temperatureOffset = climate and climate.temperatureOffset or 0
    local temperature = math.clamp((cell.temperature or 0.5) + temperatureOffset, 0, 1)
    local moisture = math.clamp(cell.moisture or 0.5, 0, 1)
    local fertility = math.clamp(cell.fertility or 0.5, 0, 1)

    local moistureScore = math.clamp(
        1 - math.abs(moisture - definition.preferredMoisture) / 0.55,
        0,
        1
    )
    local temperatureScore = math.clamp(
        1 - math.abs(temperature - definition.preferredTemperature) / 0.55,
        0,
        1
    )
    local seasonFactor = ResourceCatalog.GetSeasonMultiplier(climate and climate.season or "Spring")

    return math.clamp(fertility * moistureScore * temperatureScore * seasonFactor, 0, 1.35)
end

return ResourceCatalog

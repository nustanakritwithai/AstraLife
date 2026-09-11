local Determinism = require(script.Parent.WorldSimDeterminism)

local WorldSimClimate = {}

local SEASONS = {
    { name = "Spring", temp = 0.60, rainfall = 0.75, food = 1.10, disease = 0.85 },
    { name = "Summer", temp = 0.90, rainfall = 0.45, food = 0.95, disease = 1.00 },
    { name = "Autumn", temp = 0.65, rainfall = 0.60, food = 1.15, disease = 0.95 },
    { name = "Winter", temp = 0.30, rainfall = 0.50, food = 0.70, disease = 1.15 },
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimClimate.Update(worldState, hydrologyFolder, climateFolder, tick, seed)
    local seasonLength = 30
    local seasonIndex = math.floor((tick or 0) / seasonLength) % #SEASONS + 1
    local season = SEASONS[seasonIndex]
    local dayInSeason = (tick or 0) % seasonLength
    local transition = dayInSeason / seasonLength
    local noise = Determinism.Range(seed or 1, "climate", tick or 0, -0.08, 0.08)

    local weather = worldState:GetAttribute("Weather") or "Clear"
    local rainBoost = weather == "Rain" and 0.22 or weather == "Storm" and 0.35 or 0
    local heatBoost = weather == "Storm" and -0.05 or 0
    local rainfall = clamp(season.rainfall + rainBoost + noise * 0.5, 0, 1)
    local temperature = clamp(season.temp + heatBoost + noise, 0, 1)
    local waterAccess = hydrologyFolder and ((hydrologyFolder:GetAttribute("AverageWaterAccess") or 50) / 100) or 0.5
    local droughtPressure = clamp((1 - rainfall) * 0.52 + temperature * 0.26 + (1 - waterAccess) * 0.22, 0, 1)
    local cropMultiplier = clamp(season.food * (0.65 + rainfall * 0.45) * (1 - droughtPressure * 0.55), 0.25, 1.4)
    local diseaseClimate = clamp(season.disease * (0.65 + rainfall * 0.25 + (1 - temperature) * 0.12), 0.4, 1.5)

    climateFolder:SetAttribute("Season", season.name)
    climateFolder:SetAttribute("SeasonIndex", seasonIndex)
    climateFolder:SetAttribute("DayInSeason", dayInSeason)
    climateFolder:SetAttribute("SeasonTransition", math.floor(transition * 1000 + 0.5) / 1000)
    climateFolder:SetAttribute("Temperature", math.floor(temperature * 1000 + 0.5) / 10)
    climateFolder:SetAttribute("Rainfall", math.floor(rainfall * 1000 + 0.5) / 10)
    climateFolder:SetAttribute("DroughtPressure", math.floor(droughtPressure * 1000 + 0.5) / 10)
    climateFolder:SetAttribute("CropMultiplier", math.floor(cropMultiplier * 1000 + 0.5) / 1000)
    climateFolder:SetAttribute("DiseaseClimateMultiplier", math.floor(diseaseClimate * 1000 + 0.5) / 1000)

    return {
        season = season.name,
        seasonIndex = seasonIndex,
        temperature = temperature,
        rainfall = rainfall,
        droughtPressure = droughtPressure,
        cropMultiplier = cropMultiplier,
        diseaseClimateMultiplier = diseaseClimate,
    }
end

return WorldSimClimate

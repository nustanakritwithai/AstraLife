local WorldNoise = require(script.Parent.WorldNoise)

local ClimateModel = {}
ClimateModel.__index = ClimateModel

local DEFAULTS = {
    seed = 20904,
    secondsPerDay = 240,
    daysPerSeason = 6,
    weatherScale = 0.18,
}

local SEASONS = { "Spring", "Summer", "Autumn", "Winter" }
local SEASON_TEMPERATURE = { 0.02, 0.10, 0.00, -0.10 }
local SEASON_WETNESS = { 0.12, -0.04, 0.08, 0.02 }

local function merge(defaults, overrides)
    local result = {}
    for key, value in pairs(defaults) do
        result[key] = overrides and overrides[key] ~= nil and overrides[key] or value
    end
    return result
end

local function phaseFor(dayFraction)
    if dayFraction >= 0.20 and dayFraction < 0.28 then
        return "Dawn"
    elseif dayFraction >= 0.28 and dayFraction < 0.72 then
        return "Day"
    elseif dayFraction >= 0.72 and dayFraction < 0.80 then
        return "Dusk"
    end
    return "Night"
end

local function weatherFor(signal)
    if signal >= 0.82 then
        return "Storm"
    elseif signal >= 0.62 then
        return "Rain"
    elseif signal >= 0.46 then
        return "Cloudy"
    end
    return "Clear"
end

function ClimateModel.new(config)
    local merged = merge(DEFAULTS, config or {})
    assert(merged.secondsPerDay > 0, "secondsPerDay must be > 0")
    assert(merged.daysPerSeason >= 1, "daysPerSeason must be >= 1")
    return setmetatable({ config = merged }, ClimateModel)
end

function ClimateModel:Sample(simSeconds)
    simSeconds = math.max(0, simSeconds or 0)
    local secondsPerDay = self.config.secondsPerDay
    local dayFloat = simSeconds / secondsPerDay
    local dayIndex = math.floor(dayFloat)
    local dayFraction = dayFloat - dayIndex

    local seasonIndex = (math.floor(dayIndex / self.config.daysPerSeason) % #SEASONS) + 1
    local season = SEASONS[seasonIndex]
    local dayInSeason = dayIndex % self.config.daysPerSeason
    local seasonProgress = (dayInSeason + dayFraction) / self.config.daysPerSeason

    local solar = math.max(0, math.sin((dayFraction - 0.25) * math.pi * 2))
    local diurnalOffset = (solar - 0.45) * 0.10
    local seasonOffset = SEASON_TEMPERATURE[seasonIndex]
    local temperatureOffset = seasonOffset + diurnalOffset

    local weatherX = dayFloat * self.config.weatherScale
    local weatherNoise = WorldNoise.Value2D(self.config.seed, weatherX, seasonIndex * 0.37, 701)
    local pulseNoise = WorldNoise.Value2D(self.config.seed, weatherX * 2.1 + 17.0, seasonIndex, 719)
    local wetness = SEASON_WETNESS[seasonIndex]
    local weatherSignal = math.clamp(weatherNoise * 0.72 + pulseNoise * 0.28 + wetness, 0, 1)
    local weather = weatherFor(weatherSignal)

    local precipitation = 0
    if weather == "Rain" then
        precipitation = math.clamp(0.35 + (weatherSignal - 0.62) * 1.9, 0.35, 0.72)
    elseif weather == "Storm" then
        precipitation = math.clamp(0.72 + (weatherSignal - 0.82) * 1.5, 0.72, 1.0)
    end

    local humidity = math.clamp(0.42 + wetness + weatherSignal * 0.32, 0.18, 0.96)
    local cloudCover = math.clamp((weatherSignal - 0.25) / 0.70, 0, 1)
    local windNoise = WorldNoise.Value2D(self.config.seed, weatherX * 1.7, 9.3, 743)
    local wind = math.clamp(0.15 + windNoise * 0.55 + (weather == "Storm" and 0.25 or 0), 0, 1)
    local ambientTemperature = math.clamp(0.50 + temperatureOffset - cloudCover * 0.025, 0, 1)

    return {
        simSeconds = simSeconds,
        dayIndex = dayIndex,
        dayFraction = dayFraction,
        dayPhase = phaseFor(dayFraction),
        solar = solar,
        seasonIndex = seasonIndex,
        season = season,
        seasonProgress = seasonProgress,
        weather = weather,
        weatherSignal = weatherSignal,
        precipitation = precipitation,
        humidity = humidity,
        cloudCover = cloudCover,
        wind = wind,
        temperatureOffset = temperatureOffset,
        ambientTemperature = ambientTemperature,
    }
end

function ClimateModel:Fingerprint(samples)
    local hash = 5381
    local modulus = 4294967296
    for _, sample in ipairs(samples or {}) do
        local text = table.concat({
            sample.dayIndex or 0,
            sample.dayPhase or "",
            sample.season or "",
            sample.weather or "",
            string.format("%.5f", sample.precipitation or 0),
            string.format("%.5f", sample.humidity or 0),
            string.format("%.5f", sample.temperatureOffset or 0),
        }, "|")
        for index = 1, #text do
            hash = (hash * 33 + string.byte(text, index)) % modulus
        end
    end
    return string.format("%08x", hash)
end

return ClimateModel

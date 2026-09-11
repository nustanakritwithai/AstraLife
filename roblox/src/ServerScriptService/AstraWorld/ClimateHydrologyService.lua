local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeTerrainService = require(script.Parent.BiomeTerrainService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local ClimateModel = require(WorldModules.ClimateModel)
local HydrologySystem = require(WorldModules.HydrologySystem)
local W2Verifier = require(WorldModules.W2Verifier)

local ClimateHydrologyService = {}

local started = false
local result = nil

local function publishClimate(state, sample)
    state:SetAttribute("ClimateDay", sample.dayIndex)
    state:SetAttribute("ClimateDayFraction", sample.dayFraction)
    state:SetAttribute("ClimateHour", sample.dayFraction * 24)
    state:SetAttribute("DayPhase", sample.dayPhase)
    state:SetAttribute("Season", sample.season)
    state:SetAttribute("SeasonProgress", sample.seasonProgress)
    state:SetAttribute("Weather", sample.weather)
    state:SetAttribute("Precipitation", sample.precipitation)
    state:SetAttribute("Humidity", sample.humidity)
    state:SetAttribute("CloudCover", sample.cloudCover)
    state:SetAttribute("Wind", sample.wind)
    state:SetAttribute("AmbientTemperature", sample.ambientTemperature)
    state:SetAttribute("ClimateTemperatureOffset", sample.temperatureOffset)
end

local function publishHydrology(state, stats, totals)
    state:SetAttribute("HydrologyProcessedLast", stats.processed)
    state:SetAttribute("HydrologyChangedLast", stats.changed)
    state:SetAttribute("HydrologyWetCellsLast", stats.wetCells)
    state:SetAttribute("HydrologyDryCellsLast", stats.dryCells)
    state:SetAttribute("HydrologyRainAddedLast", stats.rainAdded)
    state:SetAttribute("HydrologyEvaporatedLast", stats.evaporated)
    state:SetAttribute("HydrologyRunoffLast", stats.runoffTransferred)
    state:SetAttribute("HydrologyCycle", totals.cycle)
    state:SetAttribute("HydrologyCursor", totals.cursor)
    state:SetAttribute("HydrologySteps", totals.steps)
    state:SetAttribute("HydrologyProcessedTotal", totals.processed)
    state:SetAttribute("HydrologyChangedTotal", totals.changed)
end

function ClimateHydrologyService.Start()
    if started then
        return result
    end
    started = true

    local terrainResult = BiomeTerrainService.Start()
    local runtime = terrainResult.runtime
    local state = runtime.state
    state:SetAttribute("Version", "W2")
    state:SetAttribute("W2Status", "BOOTING")

    local climate = ClimateModel.new({
        seed = runtime.config.seed,
        secondsPerDay = 240,
        daysPerSeason = 6,
    })
    local hydrology = HydrologySystem.new(runtime.grid, {
        batchSize = 512,
        referenceStep = runtime.config.fixedStep * 2,
    })

    local currentClimate = climate:Sample(runtime.clock.simTime)
    runtime.climateState = currentClimate
    runtime.climateModel = climate
    runtime.hydrology = hydrology
    publishClimate(state, currentClimate)

    local previousWeather = currentClimate.weather
    local previousPhase = currentClimate.dayPhase
    local previousSeason = currentClimate.season

    runtime.clock:RegisterSystem("W2.Climate", 4, function(context)
        local sample = climate:Sample(context.simTime)
        runtime.climateState = sample
        publishClimate(state, sample)

        if sample.weather ~= previousWeather then
            runtime.events:Emit("world.weather.changed", {
                from = previousWeather,
                to = sample.weather,
                precipitation = sample.precipitation,
                humidity = sample.humidity,
            }, context.tick)
            previousWeather = sample.weather
        end
        if sample.dayPhase ~= previousPhase then
            runtime.events:Emit("world.dayphase.changed", {
                from = previousPhase,
                to = sample.dayPhase,
                day = sample.dayIndex,
            }, context.tick)
            previousPhase = sample.dayPhase
        end
        if sample.season ~= previousSeason then
            runtime.events:Emit("world.season.changed", {
                from = previousSeason,
                to = sample.season,
                day = sample.dayIndex,
            }, context.tick)
            previousSeason = sample.season
        end
    end, 200)

    runtime.clock:RegisterSystem("W2.Hydrology", 2, function(context)
        local climateState = runtime.climateState or climate:Sample(context.simTime)
        local stats = hydrology:Step(
            climateState,
            runtime.dirty,
            runtime.config.fixedStep * 2
        )
        local totals = hydrology:GetTotals()
        publishHydrology(state, stats, totals)

        if stats.rainAdded > 0 or stats.runoffTransferred > 0 then
            runtime.events:Emit("world.hydrology.step", {
                processed = stats.processed,
                changed = stats.changed,
                rainAdded = stats.rainAdded,
                runoffTransferred = stats.runoffTransferred,
                cycle = stats.cycle,
            }, context.tick)
        end
    end, 300)

    local passed, checks, verifierStats = W2Verifier.Run()
    state:SetAttribute("W2Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W2Check_" .. name, value)
    end
    state:SetAttribute("W2ClimateFingerprint", verifierStats.climateFingerprint)

    runtime.events:Emit("world.climate-hydrology.started", {
        secondsPerDay = climate.config.secondsPerDay,
        daysPerSeason = climate.config.daysPerSeason,
        hydrologyBatchSize = hydrology.config.batchSize,
    }, runtime.clock.tick)

    result = {
        runtime = runtime,
        climate = climate,
        hydrology = hydrology,
        passed = passed,
        checks = checks,
    }
    return result
end

function ClimateHydrologyService.IsStarted()
    return started
end

function ClimateHydrologyService.GetResult()
    return result
end

return ClimateHydrologyService

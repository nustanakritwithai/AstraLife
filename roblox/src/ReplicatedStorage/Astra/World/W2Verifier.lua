local ClimateModel = require(script.Parent.ClimateModel)
local DirtyTracker = require(script.Parent.DirtyTracker)
local HydrologySystem = require(script.Parent.HydrologySystem)
local WorldGrid = require(script.Parent.WorldGrid)

local W2Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function seedPlainGrid(grid, patchFn)
    for z = 1, grid.depth do
        for x = 1, grid.width do
            local patch = {
                biome = "Plains",
                elevation = 0.5,
                slope = 0.1,
                water = 0,
                moisture = 0.35,
                temperature = 0.5,
                waterPotential = 0.45,
                walkable = true,
            }
            if patchFn then
                local extra = patchFn(x, z) or {}
                for key, value in pairs(extra) do
                    patch[key] = value
                end
            end
            grid:UpdateCell(x, z, patch)
        end
    end
end

function W2Verifier.Run()
    local results = {}

    local climateA = ClimateModel.new({ seed = 20904 })
    local climateB = ClimateModel.new({ seed = 20904 })
    local sampleTimes = { 0, 55, 120, 181, 240, 721, 1440, 2880 }
    local samplesA = {}
    local samplesB = {}
    for _, seconds in ipairs(sampleTimes) do
        table.insert(samplesA, climateA:Sample(seconds))
        table.insert(samplesB, climateB:Sample(seconds))
    end
    check(climateA:Fingerprint(samplesA) == climateB:Fingerprint(samplesB), "deterministicClimate", results)

    local day = climateA.config.secondsPerDay
    check(
        climateA:Sample(day * 0.22).dayPhase == "Dawn"
            and climateA:Sample(day * 0.50).dayPhase == "Day"
            and climateA:Sample(day * 0.75).dayPhase == "Dusk"
            and climateA:Sample(day * 0.90).dayPhase == "Night",
        "dayPhaseProgression",
        results
    )

    check(
        climateA:Sample(0).season == "Spring"
            and climateA:Sample(day * 6).season == "Summer"
            and climateA:Sample(day * 12).season == "Autumn"
            and climateA:Sample(day * 18).season == "Winter",
        "seasonProgression",
        results
    )

    local wetGrid = WorldGrid.new({ width = 4, depth = 4, cellSize = 8, origin = Vector3.zero })
    seedPlainGrid(wetGrid)
    local wetHydro = HydrologySystem.new(wetGrid, {
        batchSize = 16,
        evaporationRate = 0,
        rainToMoisture = 0.08,
        rainToSurface = 0.06,
    })
    local beforeMoisture = wetGrid:ReadCell(2, 2).moisture
    local wetStats = wetHydro:Step({ precipitation = 1, humidity = 1, temperatureOffset = 0 }, DirtyTracker.new(), 0.5)
    local afterWet = wetGrid:ReadCell(2, 2)
    check(afterWet.moisture > beforeMoisture and wetStats.rainAdded > 0, "rainRaisesMoisture", results)

    local dryGrid = WorldGrid.new({ width = 1, depth = 1, cellSize = 8, origin = Vector3.zero })
    seedPlainGrid(dryGrid, function()
        return { water = 0.25, moisture = 0.55, temperature = 0.9 }
    end)
    local dryHydro = HydrologySystem.new(dryGrid, {
        batchSize = 1,
        evaporationRate = 0.08,
    })
    dryHydro:Step({ precipitation = 0, humidity = 0, temperatureOffset = 0.05 }, DirtyTracker.new(), 0.5)
    check(dryGrid:ReadCell(1, 1).water < 0.25, "dryHeatEvaporatesWater", results)

    local runoffGrid = WorldGrid.new({ width = 2, depth = 1, cellSize = 8, origin = Vector3.zero })
    seedPlainGrid(runoffGrid, function(x)
        if x == 1 then
            return { elevation = 0.8, slope = 0.6, water = 0.5, moisture = 0.5 }
        end
        return { elevation = 0.2, slope = 0.05, water = 0, moisture = 0.4 }
    end)
    local runoffHydro = HydrologySystem.new(runoffGrid, {
        batchSize = 2,
        evaporationRate = 0,
        runoffFraction = 0.30,
    })
    local runoffStats = runoffHydro:Step({ precipitation = 0, humidity = 1, temperatureOffset = 0 }, DirtyTracker.new(), 0.5)
    check(runoffGrid:ReadCell(2, 1).water > 0 and runoffStats.runoffTransferred > 0, "downhillRunoff", results)

    local batchGrid = WorldGrid.new({ width = 10, depth = 10, cellSize = 8, origin = Vector3.zero })
    seedPlainGrid(batchGrid)
    local batchHydro = HydrologySystem.new(batchGrid, { batchSize = 12 })
    local batchStats = batchHydro:Step({ precipitation = 0.4, humidity = 0.7, temperatureOffset = 0 }, DirtyTracker.new(), 0.5)
    check(batchStats.processed == 12, "boundedBatchProcessing", results)

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results, {
        climateFingerprint = climateA:Fingerprint(samplesA),
        wetStats = wetStats,
        runoffStats = runoffStats,
    }
end

return W2Verifier

local WorldGrid = require(script.Parent.WorldGrid)
local HazardSystem = require(script.Parent.HazardSystem)
local EnvironmentQuery = require(script.Parent.EnvironmentQuery)

local W4Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function makeGrid(width, depth)
    local grid = WorldGrid.new({
        width = width,
        depth = depth,
        cellSize = 10,
        origin = Vector3.zero,
    })

    for z = 1, depth do
        for x = 1, width do
            grid:UpdateCell(x, z, {
                biome = "Plains",
                walkable = true,
                slope = 0.1,
                moisture = 0.05,
                water = 0,
                temperature = 0.85,
                vegetation = 1,
                vegetationCapacity = 1,
                food = 2,
                foodCapacity = 2,
                wood = 4,
                woodCapacity = 4,
            })
        end
    end
    return grid
end

local function stormClimate()
    return {
        weather = "Storm",
        precipitation = 0,
        humidity = 0.25,
        wind = 0.9,
        ambientTemperature = 0.9,
    }
end

function W4Verifier.Run()
    local results = {}

    local gridA = makeGrid(4, 2)
    local gridB = makeGrid(4, 2)
    for _, grid in ipairs({ gridA, gridB }) do
        grid:UpdateCell(1, 1, { fireIntensity = 0.70 })
        grid:UpdateCell(2, 1, { water = 0.90, moisture = 0.90 })
        grid:UpdateCell(3, 1, { moisture = 0.01 })
    end

    local beforeVegetation = gridA:ReadCell(1, 1).vegetation
    local beforeFood = gridA:ReadCell(1, 1).food
    local beforeWood = gridA:ReadCell(1, 1).wood

    local config = {
        seed = 20904,
        batchSize = 8,
        referenceStep = 0.5,
        ignitionRate = 0,
        spreadRate = 0,
    }
    local hazardsA = HazardSystem.new(gridA, config)
    local hazardsB = HazardSystem.new(gridB, config)
    local statsA = hazardsA:Step(stormClimate(), nil, 0.5)
    hazardsB:Step(stormClimate(), nil, 0.5)

    local fingerprintA = HazardSystem.Fingerprint(gridA)
    local fingerprintB = HazardSystem.Fingerprint(gridB)
    check(fingerprintA == fingerprintB, "deterministicHazards", results)

    check((gridA:ReadCell(2, 1).floodSeverity or 0) > 0.5, "floodFromSurfaceWater", results)
    check((gridA:ReadCell(3, 1).droughtSeverity or 0) > 0.5, "droughtFromDrySoil", results)
    check((gridA:ReadCell(4, 1).stormSeverity or 0) > 0.4, "stormExposure", results)

    local burningCell = gridA:ReadCell(1, 1)
    check(
        burningCell.vegetation < beforeVegetation
            and burningCell.food < beforeFood
            and burningCell.wood < beforeWood,
        "fireDamagesResources",
        results
    )

    local query = EnvironmentQuery.new(gridA)
    local burningAffordance = query:GetAffordancesAt(gridA:CellCenter(1, 1))
    check(
        burningAffordance.hazardDanger > 0.5
            and burningAffordance.dominantHazard == "Fire"
            and burningAffordance.canWalk == false
            and burningAffordance.safe == false,
        "hazardAffectsAffordance",
        results
    )

    local wetGrid = makeGrid(1, 1)
    wetGrid:UpdateCell(1, 1, {
        fireIntensity = 0.8,
        water = 0.95,
        moisture = 1,
    })
    local wetHazards = HazardSystem.new(wetGrid, {
        seed = 20904,
        batchSize = 1,
        fireGrowthRate = 0,
        fireDecayRate = 0.5,
        ignitionRate = 0,
        spreadRate = 0,
    })
    wetHazards:Step({
        weather = "Rain",
        precipitation = 1,
        wind = 0.1,
        ambientTemperature = 0.4,
    }, nil, 1)
    check((wetGrid:ReadCell(1, 1).fireIntensity or 0) < 0.8, "waterSuppressesFire", results)

    local spreadGrid = makeGrid(2, 1)
    spreadGrid:UpdateCell(1, 1, { fireIntensity = 0.9 })
    spreadGrid:UpdateCell(2, 1, { fireIntensity = 0, moisture = 0 })
    local spreadHazards = HazardSystem.new(spreadGrid, {
        seed = 20904,
        batchSize = 2,
        ignitionRate = 0,
        spreadRate = 10,
        fireGrowthRate = 0,
        fireDecayRate = 0,
    })
    spreadHazards:Step({
        weather = "Clear",
        precipitation = 0,
        wind = 1,
        ambientTemperature = 1,
    }, nil, 1)
    check((spreadGrid:ReadCell(2, 1).fireIntensity or 0) > 0, "fireSpreadsToNeighbor", results)

    local boundedGrid = makeGrid(8, 1)
    local bounded = HazardSystem.new(boundedGrid, {
        seed = 20904,
        batchSize = 2,
        ignitionRate = 0,
        spreadRate = 0,
    })
    local boundedStats = bounded:Step({
        weather = "Clear",
        precipitation = 0,
        wind = 0,
        ambientTemperature = 0.5,
    }, nil, 0.5)
    check(boundedStats.processed == 2, "batchBounded", results)

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results, {
        fingerprint = fingerprintA,
        batchProcessed = boundedStats.processed,
        fireCells = statsA.fireCells,
        floodCells = statsA.floodCells,
        droughtCells = statsA.droughtCells,
        stormCells = statsA.stormCells,
    }
end

return W4Verifier

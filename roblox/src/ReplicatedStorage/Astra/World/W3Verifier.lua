local DirtyTracker = require(script.Parent.DirtyTracker)
local WorldGrid = require(script.Parent.WorldGrid)
local LivingResourceSystem = require(script.Parent.LivingResourceSystem)
local WorldResourceTransaction = require(script.Parent.WorldResourceTransaction)

local W3Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function seedPlains(grid)
    for z = 1, grid.depth do
        for x = 1, grid.width do
            grid:UpdateCell(x, z, {
                biome = "Plains",
                terrainType = "Grass",
                fertility = 0.8,
                moisture = 0.55,
                temperature = 0.60,
                vegetation = 0.30,
                food = 0.30,
                water = 0.02,
                walkable = true,
            })
        end
    end
end

local function favorableClimate()
    return {
        season = "Spring",
        weather = "Clear",
        precipitation = 0,
        humidity = 0.55,
        temperatureOffset = 0,
    }
end

function W3Verifier.Run()
    local results = {}

    local gridA = WorldGrid.new({ width = 2, depth = 2, cellSize = 10, origin = Vector3.zero })
    local gridB = WorldGrid.new({ width = 2, depth = 2, cellSize = 10, origin = Vector3.zero })
    seedPlains(gridA)
    seedPlains(gridB)

    local systemA = LivingResourceSystem.new(gridA, { batchSize = 4 })
    local systemB = LivingResourceSystem.new(gridB, { batchSize = 4 })
    systemA:Initialize(nil, favorableClimate())
    systemB:Initialize(nil, favorableClimate())
    systemA:Step(favorableClimate(), nil, 10)
    systemB:Step(favorableClimate(), nil, 10)
    local fingerprintA = LivingResourceSystem.Fingerprint(gridA)
    local fingerprintB = LivingResourceSystem.Fingerprint(gridB)
    check(fingerprintA == fingerprintB, "deterministicResources", results)

    local growthGrid = WorldGrid.new({ width = 1, depth = 1, cellSize = 10, origin = Vector3.zero })
    seedPlains(growthGrid)
    local growthSystem = LivingResourceSystem.new(growthGrid, { batchSize = 1 })
    growthSystem:Initialize(nil, favorableClimate())
    local growthCell = growthGrid:GetCell(1, 1)
    local beforeVegetation = growthCell.vegetation
    local beforeFood = growthCell.food
    local beforeWood = growthCell.wood
    growthSystem:Step(favorableClimate(), nil, 20)
    check(
        growthCell.vegetation > beforeVegetation
            and growthCell.food > beforeFood
            and growthCell.wood > beforeWood,
        "favorableGrowth",
        results
    )

    growthGrid:UpdateCell(1, 1, {
        moisture = 0,
        vegetation = math.min(growthCell.vegetationCapacity or 0.82, 0.70),
    })
    local beforeDrought = growthCell.vegetation
    growthSystem:Step({
        season = "Summer",
        weather = "Clear",
        precipitation = 0,
        humidity = 0.08,
        temperatureOffset = 0.22,
    }, nil, 40)
    check(growthCell.vegetation < beforeDrought, "droughtDecay", results)

    local dirty = DirtyTracker.new()
    growthGrid:UpdateCell(1, 1, { food = 2.0 }, dirty)
    local ledger = WorldResourceTransaction.new(growthGrid, dirty, { maxHistory = 32 })
    local first = ledger:Withdraw(1, 1, "Food", 5, "verify-food-1")
    local duplicate = ledger:Withdraw(1, 1, "Food", 5, "verify-food-1")
    check(
        first.ok
            and math.abs(first.actual - 2.0) < 1e-6
            and first.remaining == 0
            and duplicate.duplicate
            and math.abs(duplicate.actual - first.actual) < 1e-6
            and growthGrid:GetCell(1, 1).food == 0,
        "atomicIdempotentHarvest",
        results
    )
    check((growthGrid:GetCell(1, 1).food or 0) >= 0, "noNegativeResource", results)

    growthGrid:UpdateCell(1, 1, {
        moisture = 0.55,
        temperature = 0.60,
        food = 0,
        vegetation = 0.55,
    })
    growthSystem:Step(favorableClimate(), nil, 30)
    check(growthGrid:GetCell(1, 1).food > 0, "regrowthAfterHarvest", results)

    local batchGrid = WorldGrid.new({ width = 4, depth = 4, cellSize = 10, origin = Vector3.zero })
    seedPlains(batchGrid)
    local batchSystem = LivingResourceSystem.new(batchGrid, { batchSize = 3 })
    batchSystem:Initialize(nil, favorableClimate())
    local batchStats = batchSystem:Step(favorableClimate(), nil, 1)
    check(batchStats.processed == 3, "boundedBatch", results)

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results, {
        fingerprint = fingerprintA,
        harvestedFood = first.actual,
        duplicateCount = ledger:GetStats().duplicates,
        batchProcessed = batchStats.processed,
    }
end

return W3Verifier

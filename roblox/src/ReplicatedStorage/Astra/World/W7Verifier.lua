local WorldGrid = require(script.Parent.WorldGrid)
local EcosystemSystem = require(script.Parent.EcosystemSystem)
local AffordancePolicy = require(script.Parent.AffordancePolicy)

local W7Verifier = {}

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
                slope = 0.05,
                water = 0.2,
                waterPotential = 0.5,
                moisture = 0.58,
                temperature = 0.6,
                fertility = 0.7,
                vegetation = 0.75,
                vegetationCapacity = 0.82,
                food = 6,
                foodCapacity = 7,
                wood = 2,
                woodCapacity = 3,
                danger = 0,
                hazardDanger = 0,
                hazardBlocked = false,
            })
        end
    end
    return grid
end

local function deterministicConfig(batchSize)
    return {
        batchSize = batchSize,
        referenceStep = 1,
        herbivoreBirthRate = 0.02,
        herbivoreDeathRate = 0.005,
        herbivoreFoodRate = 0.03,
        herbivoreBrowseRate = 0.002,
        predationRate = 0.03,
        predatorBirthRate = 0.01,
        predatorDeathRate = 0.006,
        scavengerBirthRate = 0.01,
        scavengerDeathRate = 0.006,
        scavengerFeedRate = 0.04,
        decompositionRate = 0.03,
    }
end

function W7Verifier.Run()
    local results = {}

    local gridA = makeGrid(4, 2)
    local gridB = makeGrid(4, 2)
    local ecoA = EcosystemSystem.new(gridA, deterministicConfig(8))
    local ecoB = EcosystemSystem.new(gridB, deterministicConfig(8))
    ecoA:Initialize(nil)
    ecoB:Initialize(nil)
    ecoA:Step(nil, 1)
    ecoB:Step(nil, 1)
    local fingerprintA = EcosystemSystem.Fingerprint(gridA)
    local fingerprintB = EcosystemSystem.Fingerprint(gridB)
    check(fingerprintA == fingerprintB, "deterministicEcosystem", results)

    local grazeGrid = makeGrid(1, 1)
    local graze = EcosystemSystem.new(grazeGrid, {
        batchSize = 1,
        referenceStep = 1,
        herbivoreBirthRate = 0,
        herbivoreDeathRate = 0,
        herbivoreFoodRate = 0.5,
        herbivoreBrowseRate = 0.1,
        predationRate = 0,
        predatorBirthRate = 0,
        predatorDeathRate = 0,
        scavengerBirthRate = 0,
        scavengerDeathRate = 0,
        scavengerFeedRate = 0,
        decompositionRate = 0,
        nutrientDecayRate = 0,
        fertilityGainRate = 0,
        fertilityLeachRate = 0,
    })
    graze:Initialize(nil)
    grazeGrid:UpdateCell(1, 1, { herbivores = 1, predators = 0, scavengers = 0 })
    local foodBefore = grazeGrid:ReadCell(1, 1).food
    local vegetationBefore = grazeGrid:ReadCell(1, 1).vegetation
    local grazeStats = graze:Step(nil, 1)
    check(
        grazeGrid:ReadCell(1, 1).food < foodBefore
            and grazeGrid:ReadCell(1, 1).vegetation < vegetationBefore
            and grazeStats.foodConsumed > 0,
        "herbivoresConsumeProducers",
        results
    )

    local predatorGrid = makeGrid(1, 1)
    local predation = EcosystemSystem.new(predatorGrid, {
        batchSize = 1,
        herbivoreBirthRate = 0,
        herbivoreDeathRate = 0,
        herbivoreFoodRate = 0,
        herbivoreBrowseRate = 0,
        predationRate = 1,
        predatorBirthRate = 0,
        predatorDeathRate = 0,
        scavengerBirthRate = 0,
        scavengerDeathRate = 0,
        scavengerFeedRate = 0,
        decompositionRate = 0,
        nutrientDecayRate = 0,
        fertilityGainRate = 0,
        fertilityLeachRate = 0,
    })
    predation:Initialize(nil)
    predatorGrid:UpdateCell(1, 1, {
        herbivores = 0.9,
        herbivoreCapacity = 1,
        predators = 0.2,
        predatorCapacity = 0.25,
        scavengers = 0,
        carrion = 0,
    })
    local preyBefore = predatorGrid:ReadCell(1, 1).herbivores
    local predStats = predation:Step(nil, 1)
    check(
        predatorGrid:ReadCell(1, 1).herbivores < preyBefore
            and predStats.predatorKills > 0
            and predatorGrid:ReadCell(1, 1).carrion > 0,
        "predationCreatesCarrion",
        results
    )

    local recycleGrid = makeGrid(1, 1)
    recycleGrid:UpdateCell(1, 1, { fertility = 0.4 })
    local recycle = EcosystemSystem.new(recycleGrid, {
        batchSize = 1,
        herbivoreBirthRate = 0,
        herbivoreDeathRate = 0,
        herbivoreFoodRate = 0,
        herbivoreBrowseRate = 0,
        predationRate = 0,
        predatorBirthRate = 0,
        predatorDeathRate = 0,
        scavengerBirthRate = 0,
        scavengerDeathRate = 0,
        scavengerFeedRate = 0,
        decompositionRate = 1,
        nutrientFromCarrion = 1,
        nutrientFromScavenging = 0,
        nutrientWasteRate = 0,
        nutrientDecayRate = 0,
        fertilityGainRate = 0.5,
        fertilityLeachRate = 0,
    })
    recycle:Initialize(nil)
    recycleGrid:UpdateCell(1, 1, {
        herbivores = 0,
        predators = 0,
        scavengers = 0,
        carrion = 1,
        nutrients = 0,
        fertility = 0.4,
        baseFertility = 0.4,
    })
    local fertilityBefore = recycleGrid:ReadCell(1, 1).fertility
    recycle:Step(nil, 1)
    local recycled = recycleGrid:ReadCell(1, 1)
    check(
        recycled.carrion < 1
            and recycled.nutrients > 0
            and recycled.fertility > fertilityBefore,
        "carrionRecyclesToFertility",
        results
    )

    local dangerCell = makeGrid(1, 1):GetCell(1, 1)
    dangerCell.ecosystemDanger = 0.5
    local restAllowed, restReason = AffordancePolicy.Evaluate(dangerCell, "Rest")
    local forageAllowed, forageReason = AffordancePolicy.Evaluate(dangerCell, "Forage")
    check(
        not restAllowed and restReason == "unsafe_to_rest"
            and not forageAllowed and forageReason == "unsafe_forage"
            and AffordancePolicy.EffectiveDanger(dangerCell) == 0.5,
        "ecosystemDangerAffectsAffordance",
        results
    )

    local habitatGrid = makeGrid(2, 1)
    habitatGrid:UpdateCell(2, 1, { hazardDanger = 0.9 })
    local habitatEco = EcosystemSystem.new(habitatGrid, { batchSize = 2 })
    habitatEco:Initialize(nil)
    check(
        habitatGrid:ReadCell(1, 1).habitatQuality > habitatGrid:ReadCell(2, 1).habitatQuality,
        "hazardsReduceHabitatQuality",
        results
    )

    local oceanGrid = makeGrid(1, 1)
    oceanGrid:UpdateCell(1, 1, { biome = "Ocean" })
    local oceanEco = EcosystemSystem.new(oceanGrid, { batchSize = 1 })
    oceanEco:Initialize(nil)
    local ocean = oceanGrid:ReadCell(1, 1)
    check(
        ocean.herbivores == 0 and ocean.predators == 0 and ocean.scavengers == 0,
        "oceanLandPopulationsEmpty",
        results
    )

    local boundedGrid = makeGrid(8, 1)
    local bounded = EcosystemSystem.new(boundedGrid, { batchSize = 2 })
    bounded:Initialize(nil)
    local boundedStats = bounded:Step(nil, 1)
    check(boundedStats.processed == 2, "batchBounded", results)

    local nonNegative = true
    for x = 1, boundedGrid.width do
        local cell = boundedGrid:ReadCell(x, 1)
        nonNegative = nonNegative
            and (cell.herbivores or 0) >= 0
            and (cell.predators or 0) >= 0
            and (cell.scavengers or 0) >= 0
            and (cell.carrion or 0) >= 0
            and (cell.nutrients or 0) >= 0
    end
    check(nonNegative, "populationsNeverNegative", results)

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
        foodConsumed = grazeStats.foodConsumed,
        predatorKills = predStats.predatorKills,
        recycledFertility = recycled.fertility,
    }
end

return W7Verifier

local DirtyTracker = require(script.Parent.DirtyTracker)
local WorldGrid = require(script.Parent.WorldGrid)
local WorldNoise = require(script.Parent.WorldNoise)
local BiomeCatalog = require(script.Parent.BiomeCatalog)
local TerrainGenerator = require(script.Parent.TerrainGenerator)

local W1Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function biomeCount(stats)
    local count = 0
    for _, amount in pairs(stats.biomes or {}) do
        if amount > 0 then
            count += 1
        end
    end
    return count
end

function W1Verifier.Run()
    local results = {}

    local a = WorldNoise.Fractal2D(20904, 12.25, 7.5, { channel = 17 })
    local b = WorldNoise.Fractal2D(20904, 12.25, 7.5, { channel = 17 })
    local c = WorldNoise.Fractal2D(20905, 12.25, 7.5, { channel = 17 })
    check(a == b and a ~= c and a >= 0 and a <= 1, "coordinateNoise", results)

    check(BiomeCatalog.Classify({ elevation = 0.1, moisture = 0.5, temperature = 0.5, slope = 0 }) == "Ocean", "oceanRule", results)
    check(BiomeCatalog.Classify({ elevation = 0.5, moisture = 0.9, temperature = 0.5, slope = 0 }) == "Wetland", "wetlandRule", results)
    check(BiomeCatalog.Classify({ elevation = 0.9, moisture = 0.4, temperature = 0.3, slope = 0 }) == "Mountain", "mountainRule", results)

    local gridA = WorldGrid.new({ width = 32, depth = 32, cellSize = 16, origin = Vector3.zero })
    local gridB = WorldGrid.new({ width = 32, depth = 32, cellSize = 16, origin = Vector3.zero })
    local dirtyA = DirtyTracker.new()
    local dirtyB = DirtyTracker.new()
    local generatorA = TerrainGenerator.new({ seed = 20904 })
    local generatorB = TerrainGenerator.new({ seed = 20904 })
    local statsA = generatorA:Generate(gridA, dirtyA)
    local statsB = generatorB:Generate(gridB, dirtyB)
    local fingerprintA = TerrainGenerator.Fingerprint(gridA)
    local fingerprintB = TerrainGenerator.Fingerprint(gridB)

    check(fingerprintA == fingerprintB, "terrainDeterminism", results)
    check(gridA:GetMaterializedCount() == 1024 and dirtyA:Count() == 1024, "fullLogicalCoverage", results)
    check(biomeCount(statsA) >= 3, "biomeDiversity", results)
    check(statsA.walkable > 0 and statsA.blocked > 0 and statsA.minHeight < statsA.maxHeight, "terrainRange", results)

    local sample = gridA:ReadCell(16, 16)
    check(
        type(sample.terrainType) == "string"
        and type(sample.elevation) == "number"
        and type(sample.slope) == "number"
        and type(sample.fertility) == "number"
        and type(sample.waterPotential) == "number",
        "cellTerrainSchema",
        results
    )

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results, {
        fingerprint = fingerprintA,
        biomeCount = biomeCount(statsA),
        walkable = statsA.walkable,
        blocked = statsA.blocked,
    }
end

return W1Verifier

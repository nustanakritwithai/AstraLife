local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldService = require(script.Parent.WorldService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local TerrainGenerator = require(WorldModules.TerrainGenerator)
local W1Verifier = require(WorldModules.W1Verifier)

local BiomeTerrainService = {}

local started = false
local result = nil

local function countBiomes(stats)
    local count = 0
    for _, amount in pairs(stats.biomes or {}) do
        if amount > 0 then
            count += 1
        end
    end
    return count
end

function BiomeTerrainService.Start()
    if started then
        return result
    end
    started = true

    local runtime = WorldService.Start()
    local state = runtime.state
    state:SetAttribute("Version", "W1")
    state:SetAttribute("W1Status", "BOOTING")

    local generator = TerrainGenerator.new({
        seed = runtime.config.seed,
    })
    local stats = generator:Generate(runtime.grid, runtime.dirty)
    local fingerprint = TerrainGenerator.Fingerprint(runtime.grid)

    state:SetAttribute("TerrainFingerprint", fingerprint)
    state:SetAttribute("TerrainGeneratedCells", stats.total)
    state:SetAttribute("TerrainWalkableCells", stats.walkable)
    state:SetAttribute("TerrainBlockedCells", stats.blocked)
    state:SetAttribute("TerrainMinHeight", stats.minHeight)
    state:SetAttribute("TerrainMaxHeight", stats.maxHeight)
    state:SetAttribute("BiomeCount", countBiomes(stats))

    for name, amount in pairs(stats.biomes) do
        state:SetAttribute("Biome_" .. name .. "_Cells", amount)
    end

    local passed, checks, verifierStats = W1Verifier.Run()
    state:SetAttribute("W1Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W1Check_" .. name, value)
    end
    state:SetAttribute("W1VerifierFingerprint", verifierStats.fingerprint)
    state:SetAttribute("W1VerifierBiomeCount", verifierStats.biomeCount)

    runtime.events:Emit("world.terrain.generated", {
        fingerprint = fingerprint,
        cells = stats.total,
        walkable = stats.walkable,
        blocked = stats.blocked,
        biomes = stats.biomes,
    }, runtime.clock.tick)

    result = {
        runtime = runtime,
        generator = generator,
        stats = stats,
        fingerprint = fingerprint,
        passed = passed,
    }
    return result
end

function BiomeTerrainService.IsStarted()
    return started
end

function BiomeTerrainService.GetResult()
    return result
end

return BiomeTerrainService

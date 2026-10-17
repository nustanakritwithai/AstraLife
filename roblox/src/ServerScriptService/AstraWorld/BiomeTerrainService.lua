local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldService = require(script.Parent.WorldService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local TerrainGenerator = require(WorldModules.TerrainGenerator)
local W1Verifier = require(WorldModules.W1Verifier)
local ResourceCatalog = require(WorldModules.ResourceCatalog)

local BiomeTerrainService = {}

local started = false
local result = nil

local POND_SEARCH_RADIUS_CELLS = 12
local MEADOW_FOOD_TARGET = 1.5

local function countBiomes(stats)
    local count = 0
    for _, amount in pairs(stats.biomes or {}) do
        if amount > 0 then
            count += 1
        end
    end
    return count
end

local function cellDistanceSquared(x1, z1, x2, z2)
    local dx = x1 - x2
    local dz = z1 - z2
    return dx * dx + dz * dz
end

-- Early-game guarantee: the colony spawn must sit within reach of drinkable
-- freshwater and forageable food regardless of where the seeded biomes land.
-- W-series owns this seeding; P-side only reads the resulting cells.
local function seedStartingHaven(runtime, stats)
    local grid = runtime.grid
    local state = runtime.state
    local origin = state:GetAttribute("ColonyOrigin") or Vector3.zero
    local originX, originZ = grid:WorldToCell(origin)
    if not originX then
        state:SetAttribute("StartingHavenSeeded", false)
        return
    end

    local candidates = {}
    for z = math.max(1, originZ - POND_SEARCH_RADIUS_CELLS), math.min(grid.depth, originZ + POND_SEARCH_RADIUS_CELLS) do
        for x = math.max(1, originX - POND_SEARCH_RADIUS_CELLS), math.min(grid.width, originX + POND_SEARCH_RADIUS_CELLS) do
            local cell = grid:ReadCell(x, z)
            if cell and cell.walkable then
                table.insert(candidates, {
                    x = x,
                    z = z,
                    distanceSquared = cellDistanceSquared(x, z, originX, originZ),
                    elevation = cell.elevation or 0,
                })
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.distanceSquared ~= b.distanceSquared then return a.distanceSquared < b.distanceSquared end
        if a.elevation ~= b.elevation then return a.elevation < b.elevation end
        if a.z ~= b.z then return a.z < b.z end
        return a.x < b.x
    end)

    if #candidates == 0 then
        state:SetAttribute("StartingHavenSeeded", false)
        return
    end

    -- Pond: the closest walkable cell becomes a spring-fed freshwater pool
    -- (water above the 0.20 drink minimum, spring potential so the drink
    -- contract survives evaporation).
    local pondCenter = candidates[1]
    local pondCells = {}
    for _, offset in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local x = pondCenter.x + offset[1]
        local z = pondCenter.z + offset[2]
        local cell = grid:ReadCell(x, z)
        if cell and cell.walkable then
            grid:UpdateCell(x, z, {
                water = math.max(cell.water or 0, 0.35),
                waterPotential = 0.90,
                moisture = math.max(cell.moisture or 0, 0.25),
            }, runtime.dirty)
            table.insert(pondCells, grid:Key(x, z))
        end
    end

    -- Forage meadow: the next closest walkable cells get food ratios that land
    -- above the 1.0 eat minimum once LivingResourceSystem converts ratio x
    -- capacity.
    local meadowKeys = {}
    for _, candidate in ipairs(candidates) do
        if #meadowKeys >= 6 then break end
        local isPond = false
        local key = grid:Key(candidate.x, candidate.z)
        for _, pondKey in ipairs(pondCells) do
            if pondKey == key then
                isPond = true
                break
            end
        end
        if not isPond then
            local cell = grid:ReadCell(candidate.x, candidate.z)
            local capacity = ResourceCatalog.Get(cell.biome).foodCapacity
            if capacity and capacity > 0 then
                local targetRatio = math.clamp(MEADOW_FOOD_TARGET / capacity, 0, 1)
                if (cell.food or 0) < targetRatio then
                    grid:UpdateCell(candidate.x, candidate.z, {
                        food = targetRatio,
                    }, runtime.dirty)
                end
                table.insert(meadowKeys, key)
            end
        end
    end

    state:SetAttribute("StartingHavenSeeded", true)
    state:SetAttribute("StartingPondCellKey", pondCells[1])
    state:SetAttribute("StartingPondSize", #pondCells)
    state:SetAttribute("StartingMeadowSize", #meadowKeys)

    -- Visual proxies so the logical haven is visible on the physical map. Pure
    -- rendering: no collision, no raycast hits, W-series owns the folder.
    local props = Workspace:FindFirstChild("AstraWorldProps")
    if not props then
        props = Instance.new("Folder")
        props.Name = "AstraWorldProps"
        props:SetAttribute("WorldVisualProxy", true)
        props.Parent = Workspace
    end
    if props:FindFirstChild("StartingHaven") then return end

    local haven = Instance.new("Folder")
    haven.Name = "StartingHaven"

    local pondPart = Instance.new("Part")
    pondPart.Name = "StartingPond"
    pondPart.Shape = Enum.PartType.Cylinder
    pondPart.Size = Vector3.new(0.3, grid.cellSize * (#pondCells * 0.9), grid.cellSize * (#pondCells * 0.9))
    pondPart.Anchored = true
    pondPart.CanCollide = false
    pondPart.CanQuery = false
    pondPart.CanTouch = false
    pondPart.Material = Enum.Material.Glass
    pondPart.Color = Color3.fromRGB(70, 140, 220)
    pondPart.Transparency = 0.45
    pondPart.Parent = haven

    local pondWorld = grid:CellCenter(pondCenter.x, pondCenter.z)
    pondPart.CFrame = CFrame.new(pondWorld.X, 0.05, pondWorld.Z) * CFrame.Angles(0, 0, math.rad(90))

    for _, key in ipairs(meadowKeys) do
        local x, z = grid:ParseKey(key)
        if x then
            local bush = Instance.new("Part")
            bush.Name = "ForageBush"
            bush.Shape = Enum.PartType.Ball
            bush.Size = Vector3.new(1.4, 1.4, 1.4)
            local center = grid:CellCenter(x, z)
            bush.Position = Vector3.new(center.X, 0.6, center.Z)
            bush.Anchored = true
            bush.CanCollide = false
            bush.CanQuery = false
            bush.CanTouch = false
            bush.Material = Enum.Material.Grass
            bush.Color = Color3.fromRGB(95, 170, 80)
            bush.Parent = haven
        end
    end

    haven.Parent = props
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

    seedStartingHaven(runtime, stats)

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

local WorldNoise = require(script.Parent.WorldNoise)
local BiomeCatalog = require(script.Parent.BiomeCatalog)

local TerrainGenerator = {}
TerrainGenerator.__index = TerrainGenerator

local DEFAULTS = {
    seed = 20904,
    seaLevel = 0.30,
    heightScale = 96,
    heightFrequency = 0.045,
    climateFrequency = 0.032,
}

local function cloneTags(tags)
    local result = {}
    for index, value in ipairs(tags or {}) do
        result[index] = value
    end
    return result
end

local function sampleField(seed, x, z, config, width, depth)
    local nx = (x - 0.5) / width
    local nz = (z - 0.5) / depth
    local dx = (nx - 0.5) / 0.5
    local dz = (nz - 0.5) / 0.5
    local distance = math.sqrt(dx * dx + dz * dz)
    local continental = math.clamp(1 - distance ^ 1.55, 0, 1)

    local base = WorldNoise.Fractal2D(seed, x, z, {
        octaves = 5,
        frequency = config.heightFrequency,
        persistence = 0.53,
        lacunarity = 2.05,
        channel = 101,
    })
    local detail = WorldNoise.Fractal2D(seed, x, z, {
        octaves = 3,
        frequency = config.heightFrequency * 2.7,
        persistence = 0.45,
        lacunarity = 2.2,
        channel = 211,
    })

    local elevation = math.clamp(base * 0.55 + detail * 0.12 + continental * 0.42 - 0.06, 0, 1)
    local moisture = WorldNoise.Fractal2D(seed, x, z, {
        octaves = 4,
        frequency = config.climateFrequency,
        persistence = 0.58,
        channel = 307,
    })

    local latitudeHeat = 1 - math.abs(nz - 0.5) * 1.18
    local temperatureNoise = WorldNoise.Fractal2D(seed, x, z, {
        octaves = 3,
        frequency = config.climateFrequency * 0.8,
        persistence = 0.5,
        channel = 401,
    })
    local altitudeCooling = math.max(0, elevation - 0.55) * 0.72
    local temperature = math.clamp(latitudeHeat * 0.62 + temperatureNoise * 0.38 - altitudeCooling, 0, 1)

    return {
        elevation = elevation,
        moisture = moisture,
        temperature = temperature,
    }
end

local function fieldKey(x, z)
    return string.format("%d:%d", x, z)
end

function TerrainGenerator.new(config)
    config = config or {}
    local merged = {}
    for key, value in pairs(DEFAULTS) do
        merged[key] = config[key] == nil and value or config[key]
    end
    return setmetatable({ config = merged }, TerrainGenerator)
end

function TerrainGenerator:Generate(grid, dirtyTracker)
    local fields = {}
    local stats = {
        total = grid.width * grid.depth,
        walkable = 0,
        blocked = 0,
        biomes = {},
        minHeight = math.huge,
        maxHeight = -math.huge,
    }

    for z = 1, grid.depth do
        for x = 1, grid.width do
            fields[fieldKey(x, z)] = sampleField(
                self.config.seed,
                x,
                z,
                self.config,
                grid.width,
                grid.depth
            )
        end
    end

    local function elevationAt(x, z)
        x = math.clamp(x, 1, grid.width)
        z = math.clamp(z, 1, grid.depth)
        return fields[fieldKey(x, z)].elevation
    end

    for z = 1, grid.depth do
        for x = 1, grid.width do
            local field = fields[fieldKey(x, z)]
            local dx = math.abs(elevationAt(x + 1, z) - elevationAt(x - 1, z))
            local dz = math.abs(elevationAt(x, z + 1) - elevationAt(x, z - 1))
            local slope = math.clamp(math.sqrt(dx * dx + dz * dz) * 4.5, 0, 1)
            local biomeName = BiomeCatalog.Classify({
                elevation = field.elevation,
                moisture = field.moisture,
                temperature = field.temperature,
                slope = slope,
            })
            local biome = BiomeCatalog.Get(biomeName)
            local height = (field.elevation - self.config.seaLevel) * self.config.heightScale
            local surfaceWater = biomeName == "Ocean" and 1 or (biomeName == "Wetland" and 0.12 or 0)
            local walkable = biome.walkable and slope < 0.78

            grid:UpdateCell(x, z, {
                biome = biomeName,
                terrainType = biome.terrain,
                elevation = field.elevation,
                height = height,
                slope = slope,
                water = surfaceWater,
                moisture = field.moisture,
                temperature = field.temperature,
                fertility = biome.fertility,
                waterPotential = biome.waterPotential,
                vegetation = biome.vegetation,
                food = biome.food,
                walkable = walkable,
                terrainTags = cloneTags(biome.tags),
            }, dirtyTracker)

            stats.biomes[biomeName] = (stats.biomes[biomeName] or 0) + 1
            if walkable then
                stats.walkable += 1
            else
                stats.blocked += 1
            end
            stats.minHeight = math.min(stats.minHeight, height)
            stats.maxHeight = math.max(stats.maxHeight, height)
        end
    end

    return stats
end

function TerrainGenerator.Fingerprint(grid)
    local hash = 5381
    local modulus = 4294967296
    for z = 1, grid.depth do
        for x = 1, grid.width do
            local cell = grid:ReadCell(x, z)
            local text = table.concat({
                x,
                z,
                cell.biome or "",
                cell.terrainType or "",
                string.format("%.4f", cell.elevation or 0),
                string.format("%.4f", cell.height or 0),
                string.format("%.4f", cell.slope or 0),
                string.format("%.4f", cell.moisture or 0),
                string.format("%.4f", cell.temperature or 0),
                cell.walkable and "1" or "0",
            }, "|")
            for index = 1, #text do
                hash = (hash * 33 + string.byte(text, index)) % modulus
            end
        end
    end
    return string.format("%08x", hash)
end

return TerrainGenerator

local HydrologySystem = {}
HydrologySystem.__index = HydrologySystem

local DEFAULTS = {
    batchSize = 512,
    referenceStep = 0.5,
    rainToMoisture = 0.030,
    rainToSurface = 0.020,
    evaporationRate = 0.0045,
    runoffFraction = 0.20,
}

local NEIGHBORS = {
    { 0, -1 },
    { 1, 0 },
    { 0, 1 },
    { -1, 0 },
}

local function merge(defaults, overrides)
    local result = {}
    for key, value in pairs(defaults) do
        result[key] = overrides and overrides[key] ~= nil and overrides[key] or value
    end
    return result
end

local function keyFor(grid, x, z)
    return grid:Key(x, z)
end

local function lowestNeighbor(grid, cell)
    local best = nil
    for _, offset in ipairs(NEIGHBORS) do
        local nx = cell.x + offset[1]
        local nz = cell.z + offset[2]
        if grid:IsInside(nx, nz) then
            local neighbor = grid:ReadCell(nx, nz)
            if neighbor and neighbor.elevation < cell.elevation then
                if not best or neighbor.elevation < best.elevation then best = neighbor end
            end
        end
    end
    return best
end

function HydrologySystem.new(grid, config)
    assert(grid, "grid is required")
    return setmetatable({
        grid = grid,
        config = merge(DEFAULTS, config or {}),
        cursor = 1,
        cycle = 0,
        baseTemperature = {},
        totals = {
            steps = 0,
            processed = 0,
            changed = 0,
            rainAdded = 0,
            evaporated = 0,
            runoffTransferred = 0,
        },
    }, HydrologySystem)
end

function HydrologySystem:Step(climate, dirtyTracker, deltaSeconds)
    climate = climate or {}
    deltaSeconds = deltaSeconds or self.config.referenceStep
    local totalCells = self.grid.width * self.grid.depth
    local count = math.min(self.config.batchSize, totalCells)
    -- A cell is only visited once per full batch cycle. Compensate its process
    -- delta so a 512-cell batch on a 4096-cell world still evolves at world time.
    local visitsPerCycle = math.max(1, math.ceil(totalCells / math.max(1, count)))
    local scale = math.clamp(
        (deltaSeconds / self.config.referenceStep) * visitsPerCycle,
        0.05,
        math.max(8, visitsPerCycle)
    )
    local planned = {}
    local waterDelta = {}
    local touched = {}
    local stats = {
        processed = 0,
        changed = 0,
        rainAdded = 0,
        evaporated = 0,
        runoffTransferred = 0,
        wetCells = 0,
        dryCells = 0,
        cycle = self.cycle,
    }

    local precipitation = math.clamp(climate.precipitation or 0, 0, 1)
    local humidity = math.clamp(climate.humidity or 0.5, 0, 1)
    local temperatureOffset = climate.temperatureOffset or 0

    for offset = 0, count - 1 do
        local index = ((self.cursor - 1 + offset) % totalCells) + 1
        local x = ((index - 1) % self.grid.width) + 1
        local z = math.floor((index - 1) / self.grid.width) + 1
        local cell = self.grid:ReadCell(x, z)
        local key = keyFor(self.grid, x, z)
        touched[key] = true
        stats.processed += 1

        if self.baseTemperature[key] == nil then self.baseTemperature[key] = cell.temperature or 0.5 end
        local localTemperature = math.clamp(self.baseTemperature[key] + temperatureOffset, 0, 1)

        if cell.biome == "Ocean" then
            planned[key] = {
                water = 1,
                moisture = math.max(cell.moisture or 0, 0.95),
                temperature = localTemperature,
            }
        else
            local slope = math.clamp(cell.slope or 0, 0, 1)
            local waterPotential = math.clamp(cell.waterPotential or 0.25, 0, 1)
            local infiltration = math.clamp(0.22 + waterPotential * 0.68 - slope * 0.18, 0.08, 0.92)
            local moistureGain = precipitation * self.config.rainToMoisture * infiltration * scale
            local surfaceGain = precipitation * self.config.rainToSurface * (1 - infiltration) * scale
            local evaporation = (1 - humidity * 0.58)
                * (0.001 + localTemperature * self.config.evaporationRate)
                * scale
            local seepage = math.max(0, waterPotential - 0.72) * 0.0015 * scale

            local nextMoisture = math.clamp(
                (cell.moisture or 0) + moistureGain + math.min(cell.water or 0, 0.25) * 0.002 * scale - evaporation * 0.65,
                0,
                1
            )
            local nextWater = math.clamp(
                (cell.water or 0) + surfaceGain + seepage - evaporation * 0.40,
                0,
                1
            )

            stats.rainAdded += moistureGain + surfaceGain
            stats.evaporated += evaporation

            local downhill = lowestNeighbor(self.grid, cell)
            if downhill and nextWater > 0.015 and slope > 0.02 then
                local transfer = math.min(
                    nextWater * self.config.runoffFraction,
                    (0.004 + slope * 0.010) * scale
                )
                if transfer > 0 then
                    local targetKey = keyFor(self.grid, downhill.x, downhill.z)
                    waterDelta[key] = (waterDelta[key] or 0) - transfer
                    waterDelta[targetKey] = (waterDelta[targetKey] or 0) + transfer
                    touched[targetKey] = true
                    stats.runoffTransferred += transfer
                end
            end

            planned[key] = {
                water = nextWater,
                moisture = nextMoisture,
                temperature = localTemperature,
            }
        end
    end

    local keys = {}
    for key in pairs(touched) do table.insert(keys, key) end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local x, z = self.grid:ParseKey(key)
        local cell = self.grid:ReadCell(x, z)
        local patch = planned[key] or {
            water = cell.water,
            moisture = cell.moisture,
            temperature = cell.temperature,
        }
        local nextWater = math.clamp((patch.water or cell.water or 0) + (waterDelta[key] or 0), 0, 1)
        if cell.biome == "Ocean" then nextWater = 1 end
        local _, changed = self.grid:UpdateCell(x, z, {
            water = nextWater,
            moisture = math.clamp(patch.moisture or cell.moisture or 0, 0, 1),
            temperature = math.clamp(patch.temperature or cell.temperature or 0.5, 0, 1),
        }, dirtyTracker)
        if changed then stats.changed += 1 end
        if nextWater >= 0.10 or (patch.moisture or 0) >= 0.70 then
            stats.wetCells += 1
        elseif (patch.moisture or 0) <= 0.30 then
            stats.dryCells += 1
        end
    end

    local oldCursor = self.cursor
    self.cursor = ((self.cursor - 1 + count) % totalCells) + 1
    if oldCursor + count > totalCells then self.cycle += 1 end
    stats.cycle = self.cycle

    self.totals.steps += 1
    self.totals.processed += stats.processed
    self.totals.changed += stats.changed
    self.totals.rainAdded += stats.rainAdded
    self.totals.evaporated += stats.evaporated
    self.totals.runoffTransferred += stats.runoffTransferred

    return stats
end

function HydrologySystem:GetTotals()
    local result = {}
    for key, value in pairs(self.totals) do result[key] = value end
    result.cursor = self.cursor
    result.cycle = self.cycle
    return result
end

return HydrologySystem

local WorldNoise = require(script.Parent.WorldNoise)

local HazardSystem = {}
HazardSystem.__index = HazardSystem

local DEFAULTS = {
    seed = 20904,
    batchSize = 512,
    referenceStep = 0.5,
    floodThreshold = 0.45,
    droughtThreshold = 0.18,
    ignitionRate = 0.020,
    spreadRate = 0.085,
    fireGrowthRate = 0.060,
    fireDecayRate = 0.035,
    burnVegetationRate = 0.030,
    burnFoodRate = 0.055,
    burnWoodRate = 0.020,
    floodVegetationDamageRate = 0.008,
    floodFoodDamageRate = 0.016,
    stormFoodDamageRate = 0.006,
    stormWoodDamageRate = 0.004,
}

local CARDINAL = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local function mergeConfig(config)
    local result = {}
    for key, value in pairs(DEFAULTS) do
        result[key] = config and config[key] ~= nil and config[key] or value
    end
    return result
end

local function linearToCell(index, width)
    local zero = index - 1
    return (zero % width) + 1, math.floor(zero / width) + 1
end

local function dominantHazard(fire, flood, drought, storm)
    local name = "None"
    local score = 0

    local function consider(hazardName, value)
        if value > score then
            name = hazardName
            score = value
        end
    end

    -- Fixed priority order makes exact-score ties deterministic.
    consider("Fire", fire)
    consider("Flood", flood * 0.82)
    consider("Drought", drought * 0.38)
    consider("Storm", storm * 0.62)

    if score < 0.05 then
        return "None"
    end
    return name
end

function HazardSystem.new(grid, config)
    assert(grid, "grid is required")
    local merged = mergeConfig(config or {})
    local totalCells = grid.width * grid.depth
    merged.batchSize = math.clamp(math.floor(merged.batchSize), 1, totalCells)

    return setmetatable({
        grid = grid,
        config = merged,
        cursor = 1,
        cycle = 0,
        steps = 0,
        totalCells = totalCells,
        totals = {
            processed = 0,
            changed = 0,
            fireCells = 0,
            floodCells = 0,
            droughtCells = 0,
            stormCells = 0,
            blockedCells = 0,
            ignitions = 0,
            spreads = 0,
            extinguished = 0,
            vegetationBurned = 0,
            foodLost = 0,
            woodLost = 0,
        },
    }, HazardSystem)
end

function HazardSystem:_neighborFire(x, z)
    local maximum = 0
    for _, offset in ipairs(CARDINAL) do
        local nx = x + offset[1]
        local nz = z + offset[2]
        if self.grid:IsInside(nx, nz) then
            local neighbor = self.grid:ReadCell(nx, nz)
            maximum = math.max(maximum, neighbor.fireIntensity or 0)
        end
    end
    return maximum
end

function HazardSystem:_computePatch(x, z, climate, effectiveDelta)
    local cell = self.grid:ReadCell(x, z)
    if not cell then
        return nil
    end

    if cell.biome == "Ocean" then
        return {
            fireIntensity = 0,
            floodSeverity = 0,
            droughtSeverity = 0,
            stormSeverity = 0,
            hazardDanger = 0,
            hazardBlocked = false,
            dominantHazard = "None",
        }, { extinguished = (cell.fireIntensity or 0) > 0 and 1 or 0 }
    end

    local moisture = math.clamp(cell.moisture or 0, 0, 1)
    local water = math.clamp(cell.water or 0, 0, 1)
    local temperature = math.clamp((climate and climate.ambientTemperature) or cell.temperature or 0.5, 0, 1)
    local precipitation = math.clamp((climate and climate.precipitation) or 0, 0, 1)
    local wind = math.clamp((climate and climate.wind) or 0, 0, 1)
    local weather = (climate and climate.weather) or "Clear"

    local floodSeverity = 0
    if water > self.config.floodThreshold then
        floodSeverity = math.clamp(
            (water - self.config.floodThreshold) / math.max(0.01, 1 - self.config.floodThreshold),
            0,
            1
        )
    end

    local droughtSeverity = 0
    if moisture < self.config.droughtThreshold and self.config.droughtThreshold > 0 then
        local dry = (self.config.droughtThreshold - moisture) / self.config.droughtThreshold
        local heat = math.clamp((temperature - 0.55) / 0.45, 0, 1)
        droughtSeverity = math.clamp(dry * (0.72 + heat * 0.28), 0, 1)
    end

    local stormSeverity = 0
    if weather == "Storm" then
        local exposure = math.clamp(0.55 + (1 - math.clamp(cell.slope or 0, 0, 1)) * 0.25, 0, 1)
        stormSeverity = math.clamp((0.45 + wind * 0.55) * exposure, 0, 1)
    end

    local oldFire = math.clamp(cell.fireIntensity or 0, 0, 1)
    local fire = oldFire
    local event = {
        ignited = false,
        spread = false,
        extinguished = false,
        vegetationBurned = 0,
        foodLost = 0,
        woodLost = 0,
    }

    local vegetationCapacity = math.max(0.0001, cell.vegetationCapacity or 1)
    local woodCapacity = math.max(0.0001, cell.woodCapacity or 1)
    local vegetationFuel = math.clamp((cell.vegetation or 0) / vegetationCapacity, 0, 1)
    local woodFuel = math.clamp((cell.wood or 0) / woodCapacity, 0, 1)
    local fuel = math.clamp(vegetationFuel * 0.65 + woodFuel * 0.35, 0, 1)
    local dryness = math.clamp(1 - moisture, 0, 1)

    if oldFire > 0 then
        local growth = self.config.fireGrowthRate
            * dryness
            * fuel
            * (0.45 + wind * 0.55)
            * effectiveDelta
        local suppression = self.config.fireDecayRate
            * (0.35 + moisture * 0.65 + water * 2.2 + precipitation * 1.5)
            * effectiveDelta
        fire = math.clamp(oldFire + growth - suppression, 0, 1)
        if oldFire >= 0.02 and fire < 0.02 then
            fire = 0
            event.extinguished = true
        end
    else
        local stepId = self.steps + 1
        local ignitionRisk = droughtSeverity
            * fuel
            * math.clamp(0.35 + temperature * 0.65, 0, 1)
            * (1 - precipitation)
            * self.config.ignitionRate
            * effectiveDelta
        local ignitionRoll = WorldNoise.Hash01(self.config.seed, x, z, 7000 + stepId)
        if ignitionRisk > 0 and ignitionRoll < ignitionRisk then
            fire = math.clamp(0.12 + ignitionRisk * 3.5, 0.12, 0.45)
            event.ignited = true
        else
            local neighborFire = self:_neighborFire(x, z)
            local spreadRisk = neighborFire
                * dryness
                * fuel
                * (0.35 + wind * 0.65)
                * (1 - precipitation)
                * self.config.spreadRate
                * effectiveDelta
            local spreadRoll = WorldNoise.Hash01(self.config.seed, x, z, 11000 + stepId)
            if spreadRisk > 0 and spreadRoll < spreadRisk then
                fire = math.clamp(0.10 + neighborFire * 0.35, 0.10, 0.55)
                event.spread = true
            end
        end
    end

    local vegetation = math.max(0, cell.vegetation or 0)
    local food = math.max(0, cell.food or 0)
    local wood = math.max(0, cell.wood or 0)

    local vegetationLoss = math.min(
        vegetation,
        fire * self.config.burnVegetationRate * effectiveDelta
            + floodSeverity * self.config.floodVegetationDamageRate * effectiveDelta
    )
    local foodLoss = math.min(
        food,
        fire * self.config.burnFoodRate * effectiveDelta
            + floodSeverity * self.config.floodFoodDamageRate * effectiveDelta
            + stormSeverity * self.config.stormFoodDamageRate * effectiveDelta
    )
    local woodLoss = math.min(
        wood,
        fire * self.config.burnWoodRate * effectiveDelta
            + stormSeverity * self.config.stormWoodDamageRate * effectiveDelta
    )

    event.vegetationBurned = vegetationLoss
    event.foodLost = foodLoss
    event.woodLost = woodLoss

    local hazardDanger = math.max(
        fire,
        floodSeverity * 0.82,
        droughtSeverity * 0.38,
        stormSeverity * 0.62
    )
    local hazardBlocked = fire >= 0.55 or floodSeverity >= 0.78

    return {
        fireIntensity = fire,
        floodSeverity = floodSeverity,
        droughtSeverity = droughtSeverity,
        stormSeverity = stormSeverity,
        hazardDanger = hazardDanger,
        hazardBlocked = hazardBlocked,
        dominantHazard = dominantHazard(fire, floodSeverity, droughtSeverity, stormSeverity),
        vegetation = math.max(0, vegetation - vegetationLoss),
        food = math.max(0, food - foodLoss),
        wood = math.max(0, wood - woodLoss),
    }, event
end

function HazardSystem:Step(climate, dirtyTracker, deltaTime)
    deltaTime = math.max(0, deltaTime or self.config.referenceStep)
    local visitsPerCycle = math.ceil(self.totalCells / self.config.batchSize)
    local effectiveDelta = deltaTime * visitsPerCycle
    local pending = {}
    local stats = {
        processed = 0,
        changed = 0,
        fireCells = 0,
        floodCells = 0,
        droughtCells = 0,
        stormCells = 0,
        blockedCells = 0,
        ignitions = 0,
        spreads = 0,
        extinguished = 0,
        vegetationBurned = 0,
        foodLost = 0,
        woodLost = 0,
        cycle = self.cycle,
        cycleCompleted = false,
        cursor = self.cursor,
    }

    for _ = 1, self.config.batchSize do
        if self.cursor > self.totalCells then
            self.cursor = 1
            self.cycle += 1
        end

        local x, z = linearToCell(self.cursor, self.grid.width)
        local patch, event = self:_computePatch(x, z, climate, effectiveDelta)
        table.insert(pending, { x = x, z = z, patch = patch, event = event })
        self.cursor += 1
        stats.processed += 1

        if self.cursor > self.totalCells then
            self.cursor = 1
            self.cycle += 1
            stats.cycleCompleted = true
        end
    end

    for _, entry in ipairs(pending) do
        local _, changed = self.grid:UpdateCell(entry.x, entry.z, entry.patch, dirtyTracker)
        if changed then
            stats.changed += 1
        end
        local cell = self.grid:ReadCell(entry.x, entry.z)
        if (cell.fireIntensity or 0) >= 0.05 then stats.fireCells += 1 end
        if (cell.floodSeverity or 0) >= 0.05 then stats.floodCells += 1 end
        if (cell.droughtSeverity or 0) >= 0.05 then stats.droughtCells += 1 end
        if (cell.stormSeverity or 0) >= 0.05 then stats.stormCells += 1 end
        if cell.hazardBlocked == true then stats.blockedCells += 1 end

        local event = entry.event or {}
        if event.ignited then stats.ignitions += 1 end
        if event.spread then stats.spreads += 1 end
        if event.extinguished then stats.extinguished += 1 end
        stats.vegetationBurned += event.vegetationBurned or 0
        stats.foodLost += event.foodLost or 0
        stats.woodLost += event.woodLost or 0
    end

    self.steps += 1
    for key, value in pairs(stats) do
        if type(value) == "number" and self.totals[key] ~= nil then
            self.totals[key] += value
        end
    end

    stats.cycle = self.cycle
    stats.cursor = self.cursor
    return stats
end

function HazardSystem:Ignite(x, z, intensity, dirtyTracker)
    local cell = self.grid:GetCell(x, z)
    if not cell or cell.biome == "Ocean" then
        return false
    end
    intensity = math.clamp(tonumber(intensity) or 0.25, 0, 1)
    local fire = math.max(cell.fireIntensity or 0, intensity)
    local _, changed = self.grid:UpdateCell(x, z, {
        fireIntensity = fire,
        hazardDanger = math.max(cell.hazardDanger or 0, fire),
        dominantHazard = "Fire",
        hazardBlocked = fire >= 0.55 or cell.hazardBlocked == true,
    }, dirtyTracker)
    return changed
end

function HazardSystem:GetTotals()
    local result = {}
    for key, value in pairs(self.totals) do
        result[key] = value
    end
    result.steps = self.steps
    result.cycle = self.cycle
    result.cursor = self.cursor
    return result
end

function HazardSystem.Fingerprint(grid)
    local hash = 5381
    local modulus = 4294967296
    for z = 1, grid.depth do
        for x = 1, grid.width do
            local cell = grid:ReadCell(x, z)
            local text = table.concat({
                x,
                z,
                string.format("%.4f", cell.fireIntensity or 0),
                string.format("%.4f", cell.floodSeverity or 0),
                string.format("%.4f", cell.droughtSeverity or 0),
                string.format("%.4f", cell.stormSeverity or 0),
                string.format("%.4f", cell.hazardDanger or 0),
                cell.hazardBlocked and "1" or "0",
                tostring(cell.dominantHazard or "None"),
            }, "|")
            for index = 1, #text do
                hash = (hash * 33 + string.byte(text, index)) % modulus
            end
        end
    end
    return string.format("%08x", hash)
end

return HazardSystem

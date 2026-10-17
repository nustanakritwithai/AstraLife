local ResourceCatalog = require(script.Parent.ResourceCatalog)

local LivingResourceSystem = {}
LivingResourceSystem.__index = LivingResourceSystem

local DEFAULTS = {
    batchSize = 512,
    referenceStep = 1,
    droughtThreshold = 0.12,
    floodThreshold = 0.78,
    droughtDecayRate = 0.0024,
    floodDecayRate = 0.0015,
}

local function cloneTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function linearToCell(index, width)
    local zero = index - 1
    return (zero % width) + 1, math.floor(zero / width) + 1
end

function LivingResourceSystem.new(grid, config)
    assert(grid, "grid is required")
    config = config or {}
    local merged = {}
    for key, value in pairs(DEFAULTS) do
        merged[key] = config[key] == nil and value or config[key]
    end

    local totalCells = grid.width * grid.depth
    merged.batchSize = math.clamp(math.floor(merged.batchSize), 1, totalCells)

    return setmetatable({
        grid = grid,
        config = merged,
        cursor = 1,
        cycle = 0,
        steps = 0,
        totalCells = totalCells,
        initialized = false,
        totals = {
            vegetation = 0,
            vegetationCapacity = 0,
            food = 0,
            foodCapacity = 0,
            wood = 0,
            woodCapacity = 0,
            processed = 0,
            changed = 0,
            grewCells = 0,
            decayedCells = 0,
            foodGrown = 0,
            woodGrown = 0,
        },
    }, LivingResourceSystem)
end

function LivingResourceSystem:Initialize(dirtyTracker, climate)
    local totals = self.totals
    totals.vegetation = 0
    totals.vegetationCapacity = 0
    totals.food = 0
    totals.foodCapacity = 0
    totals.wood = 0
    totals.woodCapacity = 0

    for z = 1, self.grid.depth do
        for x = 1, self.grid.width do
            local cell = self.grid:GetCell(x, z)
            local definition = ResourceCatalog.Get(cell.biome)
            local vegetationCapacity = definition.vegetationCapacity
            local foodCapacity = definition.foodCapacity
            local woodCapacity = definition.woodCapacity

            local initialVegetation = math.clamp(cell.vegetation or 0, 0, vegetationCapacity)
            local initialFood = math.clamp(cell.food or 0, 0, 1) * foodCapacity
            local vegetationRatio = vegetationCapacity > 0 and initialVegetation / vegetationCapacity or 0
            local initialWood = woodCapacity * vegetationRatio * 0.65
            local suitability = ResourceCatalog.Suitability(cell, climate)

            self.grid:UpdateCell(x, z, {
                vegetationCapacity = vegetationCapacity,
                foodCapacity = foodCapacity,
                woodCapacity = woodCapacity,
                vegetation = initialVegetation,
                food = initialFood,
                wood = initialWood,
                growthSuitability = suitability,
            }, dirtyTracker)

            totals.vegetation += initialVegetation
            totals.vegetationCapacity += vegetationCapacity
            totals.food += initialFood
            totals.foodCapacity += foodCapacity
            totals.wood += initialWood
            totals.woodCapacity += woodCapacity
        end
    end

    self.initialized = true
    return self:GetTotals()
end

function LivingResourceSystem:_stepCell(x, z, climate, dirtyTracker, effectiveDelta)
    local cell = self.grid:GetCell(x, z)
    if not cell or cell.biome == "Ocean" then
        return false, 0, 0, 0, false
    end

    local definition = ResourceCatalog.Get(cell.biome)
    local suitability = ResourceCatalog.Suitability(cell, climate)
    local vegetationCapacity = cell.vegetationCapacity or definition.vegetationCapacity
    local foodCapacity = cell.foodCapacity or definition.foodCapacity
    local woodCapacity = cell.woodCapacity or definition.woodCapacity

    local oldVegetation = math.clamp(cell.vegetation or 0, 0, vegetationCapacity)
    local oldFood = math.clamp(cell.food or 0, 0, foodCapacity)
    local oldWood = math.clamp(cell.wood or 0, 0, woodCapacity)

    local vegetationGap = math.max(0, vegetationCapacity - oldVegetation)
    local vegetationGrowth = definition.vegetationRate
        * suitability
        * (0.12 + vegetationGap)
        * effectiveDelta

    local stressDecay = 0
    local moisture = math.clamp(cell.moisture or 0, 0, 1)
    if moisture < self.config.droughtThreshold and self.config.droughtThreshold > 0 then
        local severity = (self.config.droughtThreshold - moisture) / self.config.droughtThreshold
        stressDecay += self.config.droughtDecayRate * severity * effectiveDelta
    end
    if cell.biome ~= "Wetland" and (cell.water or 0) > self.config.floodThreshold then
        local severity = math.clamp(
            ((cell.water or 0) - self.config.floodThreshold) / math.max(0.01, 1 - self.config.floodThreshold),
            0,
            1
        )
        stressDecay += self.config.floodDecayRate * severity * effectiveDelta
    end

    local newVegetation = math.clamp(
        oldVegetation + vegetationGrowth - stressDecay,
        0,
        vegetationCapacity
    )
    local vegetationRatio = vegetationCapacity > 0 and newVegetation / vegetationCapacity or 0

    local foodTarget = foodCapacity * vegetationRatio * math.clamp(0.45 + suitability * 0.55, 0, 1)
    local foodResponse = math.clamp(definition.foodRate * effectiveDelta, 0, 0.75)
    local newFood = math.clamp(
        oldFood + (foodTarget - oldFood) * foodResponse,
        0,
        foodCapacity
    )

    local woodTarget = woodCapacity * vegetationRatio
    local woodResponse = math.clamp(
        definition.woodRate * (0.25 + suitability * 0.75) * effectiveDelta,
        0,
        0.45
    )
    local newWood = math.clamp(
        oldWood + (woodTarget - oldWood) * woodResponse,
        0,
        woodCapacity
    )

    local _, changed = self.grid:UpdateCell(x, z, {
        vegetation = newVegetation,
        food = newFood,
        wood = newWood,
        growthSuitability = suitability,
    }, dirtyTracker)

    local vegetationDelta = newVegetation - oldVegetation
    local foodDelta = newFood - oldFood
    local woodDelta = newWood - oldWood
    local decayed = vegetationDelta < -1e-6 or foodDelta < -1e-6 or woodDelta < -1e-6

    return changed, vegetationDelta, foodDelta, woodDelta, decayed
end

function LivingResourceSystem:Step(climate, dirtyTracker, deltaTime)
    if not self.initialized then
        self:Initialize(dirtyTracker, climate)
    end

    deltaTime = math.max(0, deltaTime or self.config.referenceStep)
    local visitsPerCycle = math.ceil(self.totalCells / self.config.batchSize)
    local effectiveDelta = deltaTime * visitsPerCycle
    local stats = {
        processed = 0,
        changed = 0,
        grewCells = 0,
        decayedCells = 0,
        vegetationDelta = 0,
        foodDelta = 0,
        woodDelta = 0,
        foodGrown = 0,
        woodGrown = 0,
        cycle = self.cycle,
        cycleCompleted = false,
        cursor = self.cursor,
    }

    for _ = 1, self.config.batchSize do
        if self.cursor > self.totalCells then
            self.cursor = 1
            self.cycle += 1
            stats.cycleCompleted = true
        end

        local x, z = linearToCell(self.cursor, self.grid.width)
        local changed, vegetationDelta, foodDelta, woodDelta, decayed = self:_stepCell(
            x,
            z,
            climate,
            dirtyTracker,
            effectiveDelta
        )

        stats.processed += 1
        if changed then
            stats.changed += 1
        end
        if vegetationDelta > 1e-6 or foodDelta > 1e-6 or woodDelta > 1e-6 then
            stats.grewCells += 1
        end
        if decayed then
            stats.decayedCells += 1
        end
        stats.vegetationDelta += vegetationDelta
        stats.foodDelta += foodDelta
        stats.woodDelta += woodDelta
        stats.foodGrown += math.max(0, foodDelta)
        stats.woodGrown += math.max(0, woodDelta)

        self.totals.vegetation += vegetationDelta
        self.totals.food += foodDelta
        self.totals.wood += woodDelta

        self.cursor += 1
    end

    if self.cursor > self.totalCells then
        self.cursor = 1
        self.cycle += 1
        stats.cycleCompleted = true
    end

    self.steps += 1
    self.totals.processed += stats.processed
    self.totals.changed += stats.changed
    self.totals.grewCells += stats.grewCells
    self.totals.decayedCells += stats.decayedCells
    self.totals.foodGrown += stats.foodGrown
    self.totals.woodGrown += stats.woodGrown

    stats.cycle = self.cycle
    stats.cursor = self.cursor
    return stats
end

function LivingResourceSystem:GetTotals()
    local result = cloneTable(self.totals)
    result.cycle = self.cycle
    result.cursor = self.cursor
    result.steps = self.steps
    return result
end

function LivingResourceSystem.Fingerprint(grid)
    local hash = 5381
    local modulus = 4294967296
    for z = 1, grid.depth do
        for x = 1, grid.width do
            local cell = grid:ReadCell(x, z)
            local text = table.concat({
                x,
                z,
                cell.biome or "",
                string.format("%.4f", cell.vegetation or 0),
                string.format("%.4f", cell.vegetationCapacity or 0),
                string.format("%.4f", cell.food or 0),
                string.format("%.4f", cell.foodCapacity or 0),
                string.format("%.4f", cell.wood or 0),
                string.format("%.4f", cell.woodCapacity or 0),
                string.format("%.4f", cell.growthSuitability or 0),
            }, "|")
            for index = 1, #text do
                hash = (hash * 33 + string.byte(text, index)) % modulus
            end
        end
    end
    return string.format("%08x", hash)
end

return LivingResourceSystem

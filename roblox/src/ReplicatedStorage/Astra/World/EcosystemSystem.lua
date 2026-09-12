local EcosystemCatalog = require(script.Parent.EcosystemCatalog)

local EcosystemSystem = {}
EcosystemSystem.__index = EcosystemSystem

local DEFAULTS = {
    batchSize = 512,
    referenceStep = 1,
    herbivoreBirthRate = 0.026,
    herbivoreDeathRate = 0.006,
    herbivoreFoodRate = 0.030,
    herbivoreBrowseRate = 0.0025,
    predationRate = 0.030,
    predatorBirthRate = 0.012,
    predatorDeathRate = 0.008,
    scavengerBirthRate = 0.016,
    scavengerDeathRate = 0.007,
    scavengerFeedRate = 0.060,
    carcassYield = 0.82,
    decompositionRate = 0.030,
    nutrientFromCarrion = 0.72,
    nutrientFromScavenging = 0.38,
    nutrientWasteRate = 0.003,
    nutrientDecayRate = 0.010,
    fertilityGainRate = 0.020,
    fertilityLeachRate = 0.004,
}

local function mergeConfig(config)
    local merged = {}
    for key, value in pairs(DEFAULTS) do
        merged[key] = config and config[key] ~= nil and config[key] or value
    end
    return merged
end

local function linearToCell(index, width)
    local zero = index - 1
    return (zero % width) + 1, math.floor(zero / width) + 1
end

local function cloneTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function habitatQuality(cell)
    if not cell or cell.biome == "Ocean" then return 0 end

    local foodCapacity = math.max(0.001, cell.foodCapacity or 0.001)
    local vegetationCapacity = math.max(0.001, cell.vegetationCapacity or 0.001)
    local foodRatio = math.clamp((cell.food or 0) / foodCapacity, 0, 1)
    local vegetationRatio = math.clamp((cell.vegetation or 0) / vegetationCapacity, 0, 1)
    local waterAccess = math.clamp(math.max(
        (cell.water or 0) * 2,
        cell.waterPotential or 0,
        cell.moisture or 0
    ), 0, 1)
    local fertility = math.clamp(cell.fertility or 0.5, 0, 1)
    local hazardPenalty = 1 - math.clamp(math.max(cell.hazardDanger or 0, cell.danger or 0), 0, 1)

    return math.clamp(
        (foodRatio * 0.35 + vegetationRatio * 0.25 + waterAccess * 0.20 + fertility * 0.20)
            * hazardPenalty,
        0,
        1
    )
end

function EcosystemSystem.new(grid, config)
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
        initialized = false,
        totals = {
            herbivores = 0,
            predators = 0,
            scavengers = 0,
            carrion = 0,
            nutrients = 0,
            processed = 0,
            changed = 0,
            foodConsumed = 0,
            vegetationConsumed = 0,
            herbivoreBirths = 0,
            herbivoreDeaths = 0,
            predatorKills = 0,
            predatorBirths = 0,
            predatorDeaths = 0,
            carrionDecomposed = 0,
            scavenged = 0,
            nutrientCreated = 0,
            fertilityGain = 0,
        },
    }, EcosystemSystem)
end

function EcosystemSystem:Initialize(dirtyTracker)
    local totals = self.totals
    totals.herbivores = 0
    totals.predators = 0
    totals.scavengers = 0
    totals.carrion = 0
    totals.nutrients = 0

    for z = 1, self.grid.depth do
        for x = 1, self.grid.width do
            local cell = self.grid:GetCell(x, z)
            local profile = EcosystemCatalog.Get(cell.biome)
            local quality = habitatQuality(cell)
            local herbivoreCapacity = profile.herbivoreCapacity
            local predatorCapacity = profile.predatorCapacity
            local scavengerCapacity = profile.scavengerCapacity

            local herbivores = herbivoreCapacity * quality * 0.52
            local predators = math.min(
                predatorCapacity,
                herbivores * 0.12
            )
            local scavengers = math.min(
                scavengerCapacity,
                0.015 + herbivores * 0.035
            )
            if cell.biome == "Ocean" then
                herbivores = 0
                predators = 0
                scavengers = 0
            end

            self.grid:UpdateCell(x, z, {
                herbivoreCapacity = herbivoreCapacity,
                predatorCapacity = predatorCapacity,
                scavengerCapacity = scavengerCapacity,
                herbivores = herbivores,
                predators = predators,
                scavengers = scavengers,
                carrion = 0,
                nutrients = 0,
                baseFertility = math.clamp(cell.fertility or 0.5, 0, 1),
                habitatQuality = quality,
                ecosystemDanger = math.clamp(predators * 0.45, 0, 0.45),
            }, dirtyTracker)

            totals.herbivores += herbivores
            totals.predators += predators
            totals.scavengers += scavengers
        end
    end

    self.initialized = true
    return self:GetTotals()
end

function EcosystemSystem:_stepCell(x, z, dirtyTracker, effectiveDelta)
    local cell = self.grid:GetCell(x, z)
    if not cell then
        return false, {}
    end

    if cell.biome == "Ocean" then
        local _, changed = self.grid:UpdateCell(x, z, {
            herbivores = 0,
            predators = 0,
            scavengers = 0,
            carrion = 0,
            nutrients = 0,
            habitatQuality = 0,
            ecosystemDanger = 0,
        }, dirtyTracker)
        return changed, {}
    end

    local profile = EcosystemCatalog.Get(cell.biome)
    local quality = habitatQuality(cell)
    local hazard = math.clamp(math.max(cell.hazardDanger or 0, cell.danger or 0), 0, 1)
    local herbivoreCapacity = math.max(0, cell.herbivoreCapacity or profile.herbivoreCapacity)
    local predatorCapacity = math.max(0, cell.predatorCapacity or profile.predatorCapacity)
    local scavengerCapacity = math.max(0, cell.scavengerCapacity or profile.scavengerCapacity)

    local herbivores = math.max(0, cell.herbivores or 0)
    local predators = math.max(0, cell.predators or 0)
    local scavengers = math.max(0, cell.scavengers or 0)
    local carrion = math.max(0, cell.carrion or 0)
    local nutrients = math.max(0, cell.nutrients or 0)

    local food = math.max(0, cell.food or 0)
    local vegetation = math.max(0, cell.vegetation or 0)
    local foodCapacity = math.max(0.001, cell.foodCapacity or 0.001)
    local vegetationCapacity = math.max(0.001, cell.vegetationCapacity or 0.001)
    local foodRatio = math.clamp(food / foodCapacity, 0, 1)

    local effectiveHerbivoreCapacity = herbivoreCapacity * (0.18 + quality * 0.82)
    local herbivoreCrowding = effectiveHerbivoreCapacity > 0
        and math.clamp(herbivores / effectiveHerbivoreCapacity, 0, 2)
        or 2
    local herbivoreBirths = herbivores
        * self.config.herbivoreBirthRate
        * quality
        * math.max(0, 1 - herbivoreCrowding)
        * effectiveDelta

    local starvation = math.clamp(1 - foodRatio, 0, 1)
    local herbivoreNaturalDeaths = herbivores
        * (self.config.herbivoreDeathRate + starvation * 0.020 + hazard * 0.030)
        * effectiveDelta

    local preySupport = effectiveHerbivoreCapacity > 0
        and math.clamp(herbivores / effectiveHerbivoreCapacity, 0, 1.5)
        or 0
    local predatorKills = math.min(
        math.max(0, herbivores + herbivoreBirths - herbivoreNaturalDeaths),
        predators
            * self.config.predationRate
            * (0.35 + preySupport * 0.65)
            * effectiveDelta
    )

    local newHerbivores = math.clamp(
        herbivores + herbivoreBirths - herbivoreNaturalDeaths - predatorKills,
        0,
        math.max(0, herbivoreCapacity * 1.15)
    )

    local effectivePredatorCapacity = predatorCapacity * math.clamp(preySupport, 0, 1)
    local predatorCrowding = effectivePredatorCapacity > 0
        and math.clamp(predators / effectivePredatorCapacity, 0, 2)
        or 2
    local predatorBirths = predators
        * self.config.predatorBirthRate
        * math.clamp(preySupport, 0, 1)
        * math.max(0, 1 - predatorCrowding)
        * effectiveDelta
    local predatorDeaths = predators
        * (self.config.predatorDeathRate + math.clamp(0.55 - preySupport, 0, 0.55) * 0.035 + hazard * 0.020)
        * effectiveDelta
    local newPredators = math.clamp(
        predators + predatorBirths - predatorDeaths,
        0,
        math.max(0, predatorCapacity * 1.15)
    )

    local foodConsumed = math.min(
        food,
        newHerbivores * self.config.herbivoreFoodRate * effectiveDelta
    )
    local remainingDemand = math.max(0, newHerbivores * self.config.herbivoreBrowseRate * effectiveDelta)
    local vegetationConsumed = math.min(vegetation, remainingDemand)

    local carcassCreated = (herbivoreNaturalDeaths + predatorKills + predatorDeaths)
        * self.config.carcassYield
    local carrionBeforeProcessing = math.max(0, carrion + carcassCreated)

    local scavengerFoodSupport = math.clamp(carrionBeforeProcessing / 0.35, 0, 1)
    local scavengerCrowding = scavengerCapacity > 0
        and math.clamp(scavengers / scavengerCapacity, 0, 2)
        or 2
    local scavengerBirths = scavengers
        * self.config.scavengerBirthRate
        * scavengerFoodSupport
        * math.max(0, 1 - scavengerCrowding)
        * effectiveDelta
    local scavengerDeaths = scavengers
        * (self.config.scavengerDeathRate + (1 - scavengerFoodSupport) * 0.012 + hazard * 0.015)
        * effectiveDelta
    local newScavengers = math.clamp(
        scavengers + scavengerBirths - scavengerDeaths,
        0,
        math.max(0, scavengerCapacity * 1.15)
    )

    local scavenged = math.min(
        carrionBeforeProcessing,
        newScavengers * self.config.scavengerFeedRate * effectiveDelta
    )
    local afterScavenging = math.max(0, carrionBeforeProcessing - scavenged)
    local decompositionRate = self.config.decompositionRate
        * (0.45 + math.clamp(cell.moisture or 0.5, 0, 1) * 0.55)
    local decomposed = math.min(
        afterScavenging,
        afterScavenging * decompositionRate * effectiveDelta
    )
    local newCarrion = math.max(0, afterScavenging - decomposed)

    local nutrientCreated = (
        decomposed * self.config.nutrientFromCarrion
        + scavenged * self.config.nutrientFromScavenging
        + newHerbivores * self.config.nutrientWasteRate * effectiveDelta
    ) * profile.nutrientRetention
    local nutrientDecay = nutrients * self.config.nutrientDecayRate * effectiveDelta
    local newNutrients = math.clamp(nutrients + nutrientCreated - nutrientDecay, 0, 2)

    local fertility = math.clamp(cell.fertility or 0.5, 0, 1)
    local baseFertility = math.clamp(cell.baseFertility or fertility, 0, 1)
    local fertilityGain = newNutrients * self.config.fertilityGainRate * effectiveDelta
    local leaching = math.max(0, fertility - baseFertility)
        * self.config.fertilityLeachRate
        * effectiveDelta
    local newFertility = math.clamp(fertility + fertilityGain - leaching, 0, 1)

    local ecosystemDanger = math.clamp(
        newPredators * 0.45 + newScavengers * 0.08,
        0,
        0.55
    )

    local _, changed = self.grid:UpdateCell(x, z, {
        habitatQuality = quality,
        herbivores = newHerbivores,
        predators = newPredators,
        scavengers = newScavengers,
        carrion = newCarrion,
        nutrients = newNutrients,
        fertility = newFertility,
        ecosystemDanger = ecosystemDanger,
        food = math.max(0, food - foodConsumed),
        vegetation = math.max(0, vegetation - vegetationConsumed),
    }, dirtyTracker)

    return changed, {
        foodConsumed = foodConsumed,
        vegetationConsumed = vegetationConsumed,
        herbivoreBirths = herbivoreBirths,
        herbivoreDeaths = herbivoreNaturalDeaths,
        predatorKills = predatorKills,
        predatorBirths = predatorBirths,
        predatorDeaths = predatorDeaths,
        scavengerBirths = scavengerBirths,
        scavengerDeaths = scavengerDeaths,
        scavenged = scavenged,
        carrionCreated = carcassCreated,
        carrionDecomposed = decomposed,
        nutrientCreated = nutrientCreated,
        fertilityGain = math.max(0, newFertility - fertility),
        herbivores = newHerbivores,
        predators = newPredators,
        scavengers = newScavengers,
        carrion = newCarrion,
        nutrients = newNutrients,
    }
end

function EcosystemSystem:Step(dirtyTracker, deltaTime)
    if not self.initialized then
        self:Initialize(dirtyTracker)
    end

    deltaTime = math.max(0, deltaTime or self.config.referenceStep)
    local visitsPerCycle = math.ceil(self.totalCells / self.config.batchSize)
    local effectiveDelta = deltaTime * visitsPerCycle
    local stats = {
        processed = 0,
        changed = 0,
        foodConsumed = 0,
        vegetationConsumed = 0,
        herbivoreBirths = 0,
        herbivoreDeaths = 0,
        predatorKills = 0,
        predatorBirths = 0,
        predatorDeaths = 0,
        scavenged = 0,
        carrionDecomposed = 0,
        nutrientCreated = 0,
        fertilityGain = 0,
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
        local changed, delta = self:_stepCell(x, z, dirtyTracker, effectiveDelta)
        if changed then stats.changed += 1 end
        stats.processed += 1

        for key in pairs(stats) do
            if type(stats[key]) == "number" and delta[key] ~= nil then
                stats[key] += delta[key]
            end
        end

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
    self.totals.foodConsumed += stats.foodConsumed
    self.totals.vegetationConsumed += stats.vegetationConsumed
    self.totals.herbivoreBirths += stats.herbivoreBirths
    self.totals.herbivoreDeaths += stats.herbivoreDeaths
    self.totals.predatorKills += stats.predatorKills
    self.totals.predatorBirths += stats.predatorBirths
    self.totals.predatorDeaths += stats.predatorDeaths
    self.totals.scavenged += stats.scavenged
    self.totals.carrionDecomposed += stats.carrionDecomposed
    self.totals.nutrientCreated += stats.nutrientCreated
    self.totals.fertilityGain += stats.fertilityGain

    stats.cycle = self.cycle
    stats.cursor = self.cursor
    return stats
end

function EcosystemSystem:Recount()
    local populations = {
        herbivores = 0,
        predators = 0,
        scavengers = 0,
        carrion = 0,
        nutrients = 0,
        averageFertility = 0,
        maxEcosystemDanger = 0,
    }

    local totalCells = math.max(1, self.grid.width * self.grid.depth)
    for z = 1, self.grid.depth do
        for x = 1, self.grid.width do
            local cell = self.grid:ReadCell(x, z)
            populations.herbivores += math.max(0, cell.herbivores or 0)
            populations.predators += math.max(0, cell.predators or 0)
            populations.scavengers += math.max(0, cell.scavengers or 0)
            populations.carrion += math.max(0, cell.carrion or 0)
            populations.nutrients += math.max(0, cell.nutrients or 0)
            populations.averageFertility += math.clamp(cell.fertility or 0, 0, 1)
            populations.maxEcosystemDanger = math.max(
                populations.maxEcosystemDanger,
                cell.ecosystemDanger or 0
            )
        end
    end
    populations.averageFertility /= totalCells

    self.totals.herbivores = populations.herbivores
    self.totals.predators = populations.predators
    self.totals.scavengers = populations.scavengers
    self.totals.carrion = populations.carrion
    self.totals.nutrients = populations.nutrients
    return populations
end

function EcosystemSystem:GetTotals()
    local result = cloneTable(self.totals)
    result.steps = self.steps
    result.cycle = self.cycle
    result.cursor = self.cursor
    return result
end

function EcosystemSystem.Fingerprint(grid)
    local hash = 5381
    local modulus = 4294967296
    for z = 1, grid.depth do
        for x = 1, grid.width do
            local cell = grid:ReadCell(x, z)
            local text = table.concat({
                x,
                z,
                string.format("%.4f", cell.herbivores or 0),
                string.format("%.4f", cell.predators or 0),
                string.format("%.4f", cell.scavengers or 0),
                string.format("%.4f", cell.carrion or 0),
                string.format("%.4f", cell.nutrients or 0),
                string.format("%.4f", cell.fertility or 0),
                string.format("%.4f", cell.ecosystemDanger or 0),
            }, "|")
            for index = 1, #text do
                hash = (hash * 33 + string.byte(text, index)) % modulus
            end
        end
    end
    return string.format("%08x", hash)
end

return EcosystemSystem

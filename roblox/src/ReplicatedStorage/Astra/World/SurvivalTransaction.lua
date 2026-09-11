local SurvivalTransaction = {}
SurvivalTransaction.__index = SurvivalTransaction

local function clone(result, duplicate)
    local copy = {}
    for key, value in pairs(result) do copy[key] = value end
    copy.duplicate = duplicate == true
    return copy
end

function SurvivalTransaction.new(grid, dirtyTracker, resourceLedger, config)
    assert(grid, "grid is required")
    assert(resourceLedger, "resourceLedger is required")
    config = config or {}
    return setmetatable({
        grid = grid,
        dirty = dirtyTracker,
        resources = resourceLedger,
        waterUnit = math.max(0.001, tonumber(config.waterUnit) or 0.05),
        springMoistureCost = math.max(0.001, tonumber(config.springMoistureCost) or 0.08),
        springThreshold = math.clamp(tonumber(config.springThreshold) or 0.85, 0, 1),
        maxHistory = math.max(32, math.floor(config.maxHistory or 2048)),
        sequence = 0,
        seen = {},
        order = {},
        stats = {
            committed = 0,
            rejected = 0,
            duplicates = 0,
            foodConsumed = 0,
            surfaceWaterConsumed = 0,
            springWaterConsumed = 0,
            foodHarvested = 0,
            woodHarvested = 0,
        },
    }, SurvivalTransaction)
end

function SurvivalTransaction:_nextId(prefix)
    self.sequence += 1
    return string.format("%s:%d", prefix or "survival", self.sequence)
end

function SurvivalTransaction:_remember(id, result)
    self.seen[id] = result
    table.insert(self.order, id)
    while #self.order > self.maxHistory do
        local expired = table.remove(self.order, 1)
        self.seen[expired] = nil
    end
end

function SurvivalTransaction:_dedupe(id)
    local previous = self.seen[id]
    if previous then
        self.stats.duplicates += 1
        return clone(previous, true)
    end
    return nil
end

function SurvivalTransaction:ConsumeFood(x, z, transactionId)
    transactionId = tostring(transactionId or self:_nextId("eat"))
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

    local cell = self.grid:ReadCell(x, z)
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Eat",
        source = "world_food",
        x = x,
        z = z,
        actual = 0,
        reason = nil,
    }

    if not cell then
        result.reason = "outside_world"
    elseif cell.hazardBlocked == true or math.max(cell.danger or 0, cell.hazardDanger or 0) > 0.65 then
        result.reason = "unsafe_source"
    elseif (cell.food or 0) < 1 then
        result.reason = "insufficient_food"
    else
        local withdrawal = self.resources:Withdraw(x, z, "Food", 1, transactionId .. ":resource")
        if withdrawal.ok and withdrawal.actual >= 1 then
            result.ok = true
            result.actual = withdrawal.actual
            result.remaining = withdrawal.remaining
            self.stats.committed += 1
            self.stats.foodConsumed += withdrawal.actual
        else
            result.reason = withdrawal.reason or "withdraw_failed"
        end
    end

    if not result.ok then self.stats.rejected += 1 end
    self:_remember(transactionId, result)
    return clone(result, false)
end

function SurvivalTransaction:DrinkWater(x, z, transactionId)
    transactionId = tostring(transactionId or self:_nextId("drink"))
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

    local cell = self.grid:GetCell(x, z)
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Drink",
        source = nil,
        x = x,
        z = z,
        actual = 0,
        reason = nil,
    }

    if not cell then
        result.reason = "outside_world"
    elseif cell.hazardBlocked == true or math.max(cell.danger or 0, cell.hazardDanger or 0) > 0.65 then
        result.reason = "unsafe_source"
    elseif (cell.water or 0) >= self.waterUnit then
        local oldWater = math.max(0, cell.water or 0)
        local actual = math.min(oldWater, self.waterUnit)
        self.grid:UpdateCell(x, z, { water = math.max(0, oldWater - actual) }, self.dirty)
        result.ok = true
        result.source = "surface_water"
        result.actual = actual
        result.remaining = math.max(0, oldWater - actual)
        self.stats.committed += 1
        self.stats.surfaceWaterConsumed += actual
    elseif (cell.waterPotential or 0) >= self.springThreshold and (cell.moisture or 0) >= self.springMoistureCost then
        local oldMoisture = math.max(0, cell.moisture or 0)
        self.grid:UpdateCell(x, z, {
            moisture = math.max(0, oldMoisture - self.springMoistureCost),
        }, self.dirty)
        result.ok = true
        result.source = "spring_groundwater"
        result.actual = self.waterUnit
        result.remaining = math.max(0, oldMoisture - self.springMoistureCost)
        self.stats.committed += 1
        self.stats.springWaterConsumed += self.waterUnit
    else
        result.reason = "insufficient_water"
    end

    if not result.ok then self.stats.rejected += 1 end
    self:_remember(transactionId, result)
    return clone(result, false)
end

function SurvivalTransaction:Harvest(x, z, resourceType, amount, freeCapacity, transactionId)
    transactionId = tostring(transactionId or self:_nextId("harvest"))
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Harvest",
        source = "living_world",
        resourceType = resourceType,
        requested = math.max(0, tonumber(amount) or 0),
        actual = 0,
        reason = nil,
        x = x,
        z = z,
    }

    local cell = self.grid:ReadCell(x, z)
    local capacity = math.max(0, tonumber(freeCapacity) or 0)
    local requested = math.min(result.requested, capacity)
    if not cell then
        result.reason = "outside_world"
    elseif cell.hazardBlocked == true or math.max(cell.danger or 0, cell.hazardDanger or 0) > 0.75 then
        result.reason = "unsafe_source"
    elseif requested <= 0 then
        result.reason = capacity <= 0 and "inventory_full" or "invalid_amount"
    elseif resourceType ~= "Food" and resourceType ~= "Wood" then
        result.reason = "unsupported_resource"
    else
        local withdrawal = self.resources:Withdraw(x, z, resourceType, requested, transactionId .. ":resource")
        if withdrawal.ok and withdrawal.actual > 0 then
            result.ok = true
            result.actual = withdrawal.actual
            result.remaining = withdrawal.remaining
            self.stats.committed += 1
            if resourceType == "Food" then
                self.stats.foodHarvested += withdrawal.actual
            else
                self.stats.woodHarvested += withdrawal.actual
            end
        else
            result.reason = withdrawal.reason or "withdraw_failed"
        end
    end

    if not result.ok then self.stats.rejected += 1 end
    self:_remember(transactionId, result)
    return clone(result, false)
end

function SurvivalTransaction:GetStats()
    local result = { sequence = self.sequence, remembered = #self.order }
    for key, value in pairs(self.stats) do result[key] = value end
    return result
end

return SurvivalTransaction

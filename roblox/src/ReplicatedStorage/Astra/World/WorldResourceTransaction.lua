local WorldResourceTransaction = {}
WorldResourceTransaction.__index = WorldResourceTransaction

local RESOURCE_FIELDS = {
    Food = "food",
    Wood = "wood",
}

local function cloneResult(result, duplicate)
    return {
        ok = result.ok,
        duplicate = duplicate == true,
        transactionId = result.transactionId,
        resourceType = result.resourceType,
        requested = result.requested,
        actual = result.actual,
        remaining = result.remaining,
        x = result.x,
        z = result.z,
        cellKey = result.cellKey,
        reason = result.reason,
    }
end

function WorldResourceTransaction.new(grid, dirtyTracker, config)
    assert(grid, "grid is required")
    config = config or {}
    return setmetatable({
        grid = grid,
        dirty = dirtyTracker,
        maxHistory = math.max(16, math.floor(config.maxHistory or 1024)),
        sequence = 0,
        seen = {},
        order = {},
        totals = {
            Food = 0,
            Wood = 0,
        },
        accepted = 0,
        rejected = 0,
        duplicates = 0,
    }, WorldResourceTransaction)
end

function WorldResourceTransaction:_remember(transactionId, result)
    self.seen[transactionId] = result
    table.insert(self.order, transactionId)

    while #self.order > self.maxHistory do
        local expiredId = table.remove(self.order, 1)
        self.seen[expiredId] = nil
    end
end

function WorldResourceTransaction:_nextId()
    self.sequence += 1
    return string.format("world-resource:%d", self.sequence)
end

function WorldResourceTransaction:Withdraw(x, z, resourceType, amount, transactionId)
    transactionId = tostring(transactionId or self:_nextId())
    local previous = self.seen[transactionId]
    if previous then
        self.duplicates += 1
        return cloneResult(previous, true)
    end

    local field = RESOURCE_FIELDS[resourceType]
    amount = math.max(0, tonumber(amount) or 0)
    x = tonumber(x)
    z = tonumber(z)
    if x then x = math.floor(x) end
    if z then z = math.floor(z) end

    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        resourceType = resourceType,
        requested = amount,
        actual = 0,
        remaining = 0,
        x = x,
        z = z,
        cellKey = x and z and self.grid:Key(x, z) or nil,
        reason = nil,
    }

    if not field then
        result.reason = "unsupported_resource"
        self.rejected += 1
        self:_remember(transactionId, result)
        return cloneResult(result, false)
    end
    if not x or not z or not self.grid:IsInside(x, z) then
        result.reason = "outside_world"
        self.rejected += 1
        self:_remember(transactionId, result)
        return cloneResult(result, false)
    end

    local cell = self.grid:GetCell(x, z)
    if amount <= 0 then
        result.reason = "invalid_amount"
        result.remaining = math.max(0, cell[field] or 0)
        self.rejected += 1
        self:_remember(transactionId, result)
        return cloneResult(result, false)
    end

    local available = math.max(0, cell[field] or 0)
    local actual = math.min(available, amount)
    local remaining = math.max(0, available - actual)

    if actual > 0 then
        self.grid:UpdateCell(x, z, {
            [field] = remaining,
        }, self.dirty)
        self.totals[resourceType] = (self.totals[resourceType] or 0) + actual
        self.accepted += 1
        result.ok = true
        result.actual = actual
        result.remaining = remaining
    else
        self.rejected += 1
        result.reason = "depleted"
        result.remaining = available
    end

    self:_remember(transactionId, result)
    return cloneResult(result, false)
end

function WorldResourceTransaction:GetStats()
    return {
        sequence = self.sequence,
        accepted = self.accepted,
        rejected = self.rejected,
        duplicates = self.duplicates,
        foodWithdrawn = self.totals.Food or 0,
        woodWithdrawn = self.totals.Wood or 0,
        rememberedTransactions = #self.order,
    }
end

function WorldResourceTransaction.SupportedTypes()
    return { "Food", "Wood" }
end

return WorldResourceTransaction

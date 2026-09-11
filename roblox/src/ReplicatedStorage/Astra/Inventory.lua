local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(capacity)
    return setmetatable({
        capacity = capacity or 3,
        items = {},
        total = 0,
    }, Inventory)
end

function Inventory:Get(resourceType)
    return self.items[resourceType] or 0
end

function Inventory:GetTotal()
    return self.total
end

function Inventory:GetFree()
    return math.max(0, self.capacity - self.total)
end

function Inventory:IsFull()
    return self.total >= self.capacity
end

function Inventory:Add(resourceType, amount)
    amount = math.max(0, amount or 0)
    local accepted = math.min(amount, self:GetFree())
    if accepted <= 0 then
        return 0
    end

    self.items[resourceType] = (self.items[resourceType] or 0) + accepted
    self.total += accepted
    return accepted
end

function Inventory:Remove(resourceType, amount)
    amount = math.max(0, amount or 0)
    local current = self.items[resourceType] or 0
    local removed = math.min(current, amount)
    if removed <= 0 then
        return 0
    end

    current -= removed
    self.total -= removed

    if current <= 0 then
        self.items[resourceType] = nil
    else
        self.items[resourceType] = current
    end

    return removed
end

function Inventory:Drain()
    local out = {}
    for resourceType, amount in pairs(self.items) do
        out[resourceType] = amount
    end
    self.items = {}
    self.total = 0
    return out
end

function Inventory:Snapshot()
    local copy = {}
    for resourceType, amount in pairs(self.items) do
        copy[resourceType] = amount
    end
    return copy
end

return Inventory

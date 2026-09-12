local InventoryV2 = {}
InventoryV2.__index = InventoryV2

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

local function metadataKey(metadata)
    if type(metadata) ~= "table" then return "" end
    local keys = {}
    for key in pairs(metadata) do table.insert(keys, tostring(key)) end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do table.insert(parts, key .. "=" .. tostring(metadata[key])) end
    return table.concat(parts, ";")
end

local function compatible(a, b)
    return a.itemId == b.itemId
        and (a.durability or -1) == (b.durability or -1)
        and (a.quality or 1) == (b.quality or 1)
        and metadataKey(a.metadata) == metadataKey(b.metadata)
end

function InventoryV2.new(slotCapacity)
    return setmetatable({
        slotCapacity = math.max(1, slotCapacity or 12),
        slots = {},
        nextStackId = 1,
        transactions = {},
        transactionOrder = {},
        maxTransactions = 128,
    }, InventoryV2)
end

function InventoryV2:GetUsedSlots()
    return #self.slots
end

function InventoryV2:GetFreeSlots()
    return math.max(0, self.slotCapacity - #self.slots)
end

function InventoryV2:Count(itemId)
    local total = 0
    for _, stack in ipairs(self.slots) do
        if stack.itemId == itemId then total += stack.quantity end
    end
    return total
end

function InventoryV2:_remember(transactionId, result)
    if not transactionId or transactionId == "" then return end
    if self.transactions[transactionId] == nil then
        table.insert(self.transactionOrder, transactionId)
    end
    self.transactions[transactionId] = clone(result)
    while #self.transactionOrder > self.maxTransactions do
        local old = table.remove(self.transactionOrder, 1)
        self.transactions[old] = nil
    end
end

function InventoryV2:Add(spec, transactionId)
    if transactionId and self.transactions[transactionId] then return clone(self.transactions[transactionId]) end
    assert(type(spec) == "table" and type(spec.itemId) == "string", "item spec required")
    local remaining = math.max(0, math.floor(spec.quantity or 0))
    local maxStack = math.max(1, math.floor(spec.maxStack or 1))
    local requested = remaining

    for _, stack in ipairs(self.slots) do
        if remaining <= 0 then break end
        if compatible(stack, spec) and stack.quantity < stack.maxStack then
            local accepted = math.min(remaining, stack.maxStack - stack.quantity)
            stack.quantity += accepted
            remaining -= accepted
        end
    end

    while remaining > 0 and #self.slots < self.slotCapacity do
        local accepted = math.min(remaining, maxStack)
        table.insert(self.slots, {
            stackId = self.nextStackId,
            itemId = spec.itemId,
            quantity = accepted,
            maxStack = maxStack,
            durability = spec.durability,
            quality = spec.quality or 1,
            metadata = clone(spec.metadata or {}),
        })
        self.nextStackId += 1
        remaining -= accepted
    end

    local result = { requested = requested, accepted = requested - remaining, rejected = remaining }
    self:_remember(transactionId, result)
    return result
end

function InventoryV2:ForgetTransaction(transactionId)
    if not transactionId or transactionId == "" then return false end
    if self.transactions[transactionId] == nil then return false end
    self.transactions[transactionId] = nil
    for index, id in ipairs(self.transactionOrder) do
        if id == transactionId then
            table.remove(self.transactionOrder, index)
            break
        end
    end
    return true
end

function InventoryV2:Remove(itemId, quantity, transactionId)
    if transactionId and self.transactions[transactionId] then return clone(self.transactions[transactionId]) end
    local remaining = math.max(0, math.floor(quantity or 0))
    local requested = remaining
    for index = #self.slots, 1, -1 do
        if remaining <= 0 then break end
        local stack = self.slots[index]
        if stack.itemId == itemId then
            local removed = math.min(remaining, stack.quantity)
            stack.quantity -= removed
            remaining -= removed
            if stack.quantity <= 0 then table.remove(self.slots, index) end
        end
    end
    local result = { requested = requested, removed = requested - remaining, missing = remaining }
    self:_remember(transactionId, result)
    return result
end

function InventoryV2:Split(stackId, quantity)
    if #self.slots >= self.slotCapacity then return nil, "no_free_slot" end
    quantity = math.max(1, math.floor(quantity or 1))
    for _, stack in ipairs(self.slots) do
        if stack.stackId == stackId then
            if quantity >= stack.quantity then return nil, "split_too_large" end
            stack.quantity -= quantity
            local copy = clone(stack)
            copy.stackId = self.nextStackId
            copy.quantity = quantity
            self.nextStackId += 1
            table.insert(self.slots, copy)
            return copy
        end
    end
    return nil, "stack_not_found"
end

function InventoryV2:Snapshot()
    local slots = {}
    for index, stack in ipairs(self.slots) do slots[index] = clone(stack) end
    return { slotCapacity = self.slotCapacity, usedSlots = #slots, slots = slots }
end

return InventoryV2

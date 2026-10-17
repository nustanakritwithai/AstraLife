local StationContainer = {}
StationContainer.__index = StationContainer

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

function StationContainer.new(profile)
    assert(profile and profile.bays, "container profile required")
    local bays = {}
    for name, spec in pairs(profile.bays) do
        bays[name] = { spec = clone(spec), stacks = {} }
    end
    return setmetatable({ bays = bays, seen = {} }, StationContainer)
end

function StationContainer:Add(bayName, item, transactionId)
    if transactionId and self.seen[transactionId] then return clone(self.seen[transactionId]), "duplicate" end
    local bay = self.bays[bayName]
    if not bay then return nil, "unknown_bay" end
    if bay.spec.accepts ~= "any" and item.tag ~= bay.spec.accepts then return nil, "item_not_accepted" end
    local maxStack = math.max(1, math.floor(item.maxStack or 1))
    local remaining = math.max(0, math.floor(item.quantity or 0))
    local requested = remaining
    for _, stack in ipairs(bay.stacks) do
        if remaining <= 0 then break end
        if stack.itemId == item.itemId and stack.quantity < stack.maxStack then
            local accepted = math.min(remaining, stack.maxStack - stack.quantity)
            stack.quantity += accepted
            remaining -= accepted
        end
    end
    while remaining > 0 and #bay.stacks < bay.spec.slots do
        local accepted = math.min(remaining, maxStack)
        table.insert(bay.stacks, { itemId = item.itemId, quantity = accepted, maxStack = maxStack, tag = item.tag })
        remaining -= accepted
    end
    local result = { requested = requested, accepted = requested - remaining, rejected = remaining }
    if transactionId then self.seen[transactionId] = result end
    return clone(result), "ok"
end

function StationContainer:Remove(bayName, itemId, quantity, transactionId)
    if transactionId and self.seen[transactionId] then return clone(self.seen[transactionId]), "duplicate" end
    local bay = self.bays[bayName]
    if not bay then return nil, "unknown_bay" end
    local remaining = math.max(0, math.floor(quantity or 0))
    local requested = remaining
    for index = #bay.stacks, 1, -1 do
        if remaining <= 0 then break end
        local stack = bay.stacks[index]
        if stack.itemId == itemId then
            local removed = math.min(remaining, stack.quantity)
            stack.quantity -= removed
            remaining -= removed
            if stack.quantity == 0 then table.remove(bay.stacks, index) end
        end
    end
    local result = { requested = requested, removed = requested - remaining, missing = remaining }
    if transactionId then self.seen[transactionId] = result end
    return clone(result), "ok"
end

function StationContainer:Snapshot()
    local out = {}
    for name, bay in pairs(self.bays) do out[name] = clone(bay.stacks) end
    return out
end

return StationContainer

local Memory = {}
Memory.__index = Memory

function Memory.new(config)
    return setmetatable({
        config = config,
        short = {},
        long = {},
    }, Memory)
end

local function push(list, item, limit)
    table.insert(list, 1, item)
    while #list > limit do
        table.remove(list)
    end
end

function Memory:Remember(tick, kind, data, importance)
    local item = {
        tick = tick,
        time = os.clock(),
        kind = kind,
        data = data,
        importance = importance or 0.5,
    }

    push(self.short, item, self.config.ShortMemoryLimit)

    if item.importance >= 0.75 then
        push(self.long, item, self.config.LongMemoryLimit)
    end

    return item
end

function Memory:Latest(kind)
    for _, item in ipairs(self.short) do
        if item.kind == kind then
            return item
        end
    end

    for _, item in ipairs(self.long) do
        if item.kind == kind then
            return item
        end
    end

    return nil
end

function Memory:Count()
    return #self.short, #self.long
end

return Memory

local DirtyTracker = {}
DirtyTracker.__index = DirtyTracker

function DirtyTracker.new()
    return setmetatable({
        _queue = {},
        _head = 1,
        _tail = 0,
        _dirty = {},
        _versions = {},
        _count = 0,
    }, DirtyTracker)
end

function DirtyTracker:Mark(key)
    key = tostring(key)
    self._versions[key] = (self._versions[key] or 0) + 1
    if self._dirty[key] then
        return self._versions[key]
    end

    self._dirty[key] = true
    self._count += 1
    self._tail += 1
    self._queue[self._tail] = key
    return self._versions[key]
end

function DirtyTracker:MarkMany(keys)
    for _, key in ipairs(keys) do
        self:Mark(key)
    end
end

function DirtyTracker:IsDirty(key)
    return self._dirty[tostring(key)] == true
end

function DirtyTracker:GetVersion(key)
    return self._versions[tostring(key)] or 0
end

function DirtyTracker:Count()
    return self._count
end

function DirtyTracker:Drain(maxItems)
    maxItems = maxItems or math.huge
    local result = {}

    while self._head <= self._tail and #result < maxItems do
        local key = self._queue[self._head]
        self._queue[self._head] = nil
        self._head += 1

        if key and self._dirty[key] then
            self._dirty[key] = nil
            self._count -= 1
            table.insert(result, {
                key = key,
                version = self._versions[key] or 0,
            })
        end
    end

    if self._head > self._tail then
        self._queue = {}
        self._head = 1
        self._tail = 0
    end

    return result
end

function DirtyTracker:Clear()
    self._queue = {}
    self._head = 1
    self._tail = 0
    self._dirty = {}
    self._count = 0
end

return DirtyTracker

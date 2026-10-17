local WorldEventBus = {}
WorldEventBus.__index = WorldEventBus

function WorldEventBus.new(maxQueued)
    return setmetatable({
        _maxQueued = maxQueued or 256,
        _queue = {},
        _subscribers = {},
        _sequence = 0,
        _dropped = 0,
    }, WorldEventBus)
end

function WorldEventBus:Subscribe(topic, handler)
    assert(type(handler) == "function", "handler must be a function")
    topic = tostring(topic)
    local bucket = self._subscribers[topic]
    if not bucket then
        bucket = {}
        self._subscribers[topic] = bucket
    end

    local entry = { handler = handler, connected = true }
    table.insert(bucket, entry)

    return {
        Disconnect = function()
            entry.connected = false
        end,
    }
end

function WorldEventBus:Emit(topic, payload, tick)
    self._sequence += 1
    local event = {
        sequence = self._sequence,
        topic = tostring(topic),
        tick = tick or 0,
        payload = payload,
    }

    if #self._queue >= self._maxQueued then
        table.remove(self._queue, 1)
        self._dropped += 1
    end

    table.insert(self._queue, event)
    return event
end

local function dispatchBucket(bucket, event)
    if not bucket then
        return
    end
    for _, entry in ipairs(bucket) do
        if entry.connected then
            local ok, err = pcall(entry.handler, event)
            if not ok then
                warn("[AstraLife][WorldEventBus] subscriber error:", err)
            end
        end
    end
end

function WorldEventBus:Flush(maxEvents)
    maxEvents = maxEvents or #self._queue
    local dispatched = 0

    while #self._queue > 0 and dispatched < maxEvents do
        local event = table.remove(self._queue, 1)
        dispatchBucket(self._subscribers[event.topic], event)
        dispatchBucket(self._subscribers["*"], event)
        dispatched += 1
    end

    return dispatched
end

function WorldEventBus:GetStats()
    return {
        queued = #self._queue,
        sequence = self._sequence,
        dropped = self._dropped,
    }
end

return WorldEventBus

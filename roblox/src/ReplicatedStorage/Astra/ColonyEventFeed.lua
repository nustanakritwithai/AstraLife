local ColonyEventFeed = {}
ColonyEventFeed.__index = ColonyEventFeed

local function clampText(text, limit)
    text = tostring(text or "")
    if #text <= limit then
        return text
    end
    return string.sub(text, 1, limit - 3) .. "..."
end

function ColonyEventFeed.new(maxEvents)
    return setmetatable({
        maxEvents = math.max(10, maxEvents or 60),
        sequence = 0,
        events = {},
        lastSeen = {},
    }, ColonyEventFeed)
end

function ColonyEventFeed:Push(tick, kind, text, severity, source)
    tick = tonumber(tick) or 0
    kind = tostring(kind or "system")
    severity = tostring(severity or "info")
    source = tostring(source or "world")
    text = clampText(text, 180)

    local dedupeKey = table.concat({kind, source, text}, "|")
    local lastTick = self.lastSeen[dedupeKey]
    if lastTick and tick - lastTick <= 1 then
        return nil
    end
    self.lastSeen[dedupeKey] = tick

    self.sequence += 1
    local event = {
        id = self.sequence,
        tick = tick,
        kind = kind,
        severity = severity,
        source = source,
        text = text,
    }

    table.insert(self.events, event)
    while #self.events > self.maxEvents do
        table.remove(self.events, 1)
    end

    return event
end

function ColonyEventFeed:Snapshot(limit)
    limit = math.max(1, math.min(limit or 25, self.maxEvents))
    local first = math.max(1, #self.events - limit + 1)
    local out = {}
    for i = first, #self.events do
        local event = self.events[i]
        table.insert(out, {
            id = event.id,
            tick = event.tick,
            kind = event.kind,
            severity = event.severity,
            source = event.source,
            text = event.text,
        })
    end
    return out
end

return ColonyEventFeed

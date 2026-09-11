local WorldSimReplay = {}

local CAPACITY = 240
local history = {}
local lastFingerprint = nil

function WorldSimReplay.Record(snapshot, replayFolder)
    local changed = snapshot.fingerprint ~= lastFingerprint
    lastFingerprint = snapshot.fingerprint
    table.insert(history, {
        tick = snapshot.tick,
        fingerprint = snapshot.fingerprint,
        changed = changed,
        agentCount = #snapshot.agents,
        resourceCount = #snapshot.resources,
        structureCount = #snapshot.structures,
    })
    while #history > CAPACITY do table.remove(history, 1) end

    if replayFolder then
        replayFolder:SetAttribute("LastTick", snapshot.tick)
        replayFolder:SetAttribute("LastFingerprint", snapshot.fingerprint)
        replayFolder:SetAttribute("HistoryCount", #history)
        replayFolder:SetAttribute("LastChanged", changed)
    end
    return changed
end

function WorldSimReplay.GetHistory()
    local out = {}
    for i, entry in ipairs(history) do out[i] = table.clone(entry) end
    return out
end

function WorldSimReplay.GetFingerprint(tick)
    for i = #history, 1, -1 do
        if history[i].tick == tick then return history[i].fingerprint end
    end
    return nil
end

function WorldSimReplay.Verify(tick, expectedFingerprint)
    local actual = WorldSimReplay.GetFingerprint(tick)
    return actual ~= nil and actual == expectedFingerprint, actual
end

return WorldSimReplay

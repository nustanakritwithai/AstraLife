local WorldSimMetrics = {}

local DEFAULTS = {
    TotalTicks = 0,
    SnapshotsRecorded = 0,
    WorldStateChanges = 0,
    SkillUps = 0,
    InjuryEvents = 0,
    RelationshipInteractions = 0,
    CriticalTransitions = 0,
}

function WorldSimMetrics.Ensure(folder)
    for key, value in pairs(DEFAULTS) do
        if folder:GetAttribute(key) == nil then folder:SetAttribute(key, value) end
    end
end

function WorldSimMetrics.Increment(folder, key, amount)
    WorldSimMetrics.Ensure(folder)
    local nextValue = (folder:GetAttribute(key) or 0) + (amount or 1)
    folder:SetAttribute(key, nextValue)
    return nextValue
end

function WorldSimMetrics.Gauge(folder, key, value)
    folder:SetAttribute(key, value)
    return value
end

function WorldSimMetrics.RecordSnapshot(folder, changed)
    WorldSimMetrics.Increment(folder, "SnapshotsRecorded", 1)
    if changed then WorldSimMetrics.Increment(folder, "WorldStateChanges", 1) end
end

return WorldSimMetrics

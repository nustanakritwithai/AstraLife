local DiplomacyTreaties = {}
DiplomacyTreaties.__index = DiplomacyTreaties

local ALLOWED = {
    trade = true,
    alliance = true,
    peace = true,
    tribute = true,
    embargo = true,
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function DiplomacyTreaties.new(maxHistory)
    return setmetatable({
        treaties = {},
        history = {},
        maxHistory = math.max(20, maxHistory or 200),
        revision = 0,
    }, DiplomacyTreaties)
end

function DiplomacyTreaties:_record(event)
    self.revision += 1
    event.revision = self.revision
    table.insert(self.history, event)
    while #self.history > self.maxHistory do table.remove(self.history, 1) end
end

function DiplomacyTreaties:Propose(id, treatyType, partyA, partyB, tick, duration, terms)
    if self.treaties[id] then return true, "duplicate" end
    if not ALLOWED[treatyType] then return false, "invalid_type" end
    if not partyA or not partyB or partyA == partyB then return false, "invalid_parties" end
    local startTick = math.max(0, tonumber(tick) or 0)
    local ttl = math.max(1, tonumber(duration) or 100)
    self.treaties[id] = {
        id = id,
        treatyType = treatyType,
        partyA = tostring(partyA),
        partyB = tostring(partyB),
        proposedTick = startTick,
        activeTick = nil,
        expireTick = startTick + ttl,
        status = "proposed",
        terms = terms or {},
        breakReason = nil,
    }
    self:_record({ kind = "proposed", treatyId = id, treatyType = treatyType, partyA = partyA, partyB = partyB, tick = startTick })
    return true, "proposed"
end

function DiplomacyTreaties:Activate(id, tick)
    local t = self.treaties[id]
    if not t then return false, "missing" end
    if t.status == "active" then return true, "duplicate" end
    if t.status ~= "proposed" then return false, "invalid_status" end
    t.status = "active"
    t.activeTick = math.max(0, tonumber(tick) or t.proposedTick)
    if t.expireTick <= t.activeTick then t.expireTick = t.activeTick + 1 end
    self:_record({ kind = "activated", treatyId = id, tick = t.activeTick })
    return true, "active"
end

function DiplomacyTreaties:Break(id, tick, reason)
    local t = self.treaties[id]
    if not t then return false, "missing" end
    if t.status == "broken" then return true, "duplicate" end
    if t.status == "expired" then return false, "expired" end
    t.status = "broken"
    t.brokenTick = math.max(0, tonumber(tick) or 0)
    t.breakReason = reason or "unspecified"
    self:_record({ kind = "broken", treatyId = id, tick = t.brokenTick, reason = t.breakReason })
    return true, "broken"
end

function DiplomacyTreaties:Advance(tick)
    local now = math.max(0, tonumber(tick) or 0)
    local expired = 0
    for _, t in pairs(self.treaties) do
        if (t.status == "active" or t.status == "proposed") and now >= t.expireTick then
            t.status = "expired"
            t.expiredTick = now
            expired += 1
            self:_record({ kind = "expired", treatyId = t.id, tick = now })
        end
    end
    return expired
end

function DiplomacyTreaties:Get(id)
    local t = self.treaties[id]
    return t and copy(t) or nil
end

function DiplomacyTreaties:Snapshot()
    local counts = { proposed = 0, active = 0, broken = 0, expired = 0 }
    local typeCounts = {}
    for _, t in pairs(self.treaties) do
        counts[t.status] = (counts[t.status] or 0) + 1
        typeCounts[t.treatyType] = (typeCounts[t.treatyType] or 0) + 1
    end
    return {
        revision = self.revision,
        treatyCount = counts.proposed + counts.active + counts.broken + counts.expired,
        proposedCount = counts.proposed,
        activeCount = counts.active,
        brokenCount = counts.broken,
        expiredCount = counts.expired,
        typeCounts = typeCounts,
        historyCount = #self.history,
    }
end

return DiplomacyTreaties

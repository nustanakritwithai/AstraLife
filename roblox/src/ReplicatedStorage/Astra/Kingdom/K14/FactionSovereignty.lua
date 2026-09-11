local FactionSovereignty = {}
FactionSovereignty.__index = FactionSovereignty

local function countMap(map)
    local n = 0
    for _ in pairs(map) do n += 1 end
    return n
end

function FactionSovereignty.new(maxHistory)
    return setmetatable({
        factions = {},
        claims = {},
        history = {},
        revision = 0,
        maxHistory = math.max(20, maxHistory or 200),
    }, FactionSovereignty)
end

function FactionSovereignty:_record(event)
    self.revision += 1
    event.revision = self.revision
    table.insert(self.history, event)
    while #self.history > self.maxHistory do table.remove(self.history, 1) end
end

function FactionSovereignty:EnsureFaction(id, name)
    if type(id) ~= "string" or id == "" then return false, "invalid_faction_id" end
    local faction = self.factions[id]
    if not faction then
        faction = {
            id = id,
            name = name or id,
            rulerId = nil,
            treasuryRef = nil,
            overlordId = nil,
            vassals = {},
            tributeRate = 0,
            reputation = 50,
        }
        self.factions[id] = faction
        self:_record({ kind = "faction_created", factionId = id })
    elseif name and name ~= "" then
        faction.name = name
    end
    return true, faction
end

function FactionSovereignty:SetRuler(factionId, rulerId)
    local ok, faction = self:EnsureFaction(factionId)
    if not ok then return false, faction end
    faction.rulerId = rulerId and tostring(rulerId) or nil
    self:_record({ kind = "ruler_set", factionId = factionId, rulerId = faction.rulerId })
    return true, "updated"
end

function FactionSovereignty:SetTreasuryRef(factionId, treasuryRef)
    local ok, faction = self:EnsureFaction(factionId)
    if not ok then return false, faction end
    faction.treasuryRef = treasuryRef and tostring(treasuryRef) or nil
    self:_record({ kind = "treasury_ref_set", factionId = factionId, treasuryRef = faction.treasuryRef })
    return true, "updated"
end

function FactionSovereignty:ClaimSettlement(factionId, settlementId, legitimacy)
    local ok, faction = self:EnsureFaction(factionId)
    if not ok then return false, faction end
    if type(settlementId) ~= "string" or settlementId == "" then return false, "invalid_settlement_id" end
    self.claims[settlementId] = {
        settlementId = settlementId,
        factionId = factionId,
        legitimacy = math.max(0, math.min(100, tonumber(legitimacy) or 50)),
    }
    self:_record({ kind = "settlement_claimed", factionId = factionId, settlementId = settlementId })
    return true, "claimed"
end

function FactionSovereignty:ReleaseSettlement(settlementId)
    if not self.claims[settlementId] then return false, "missing_claim" end
    local old = self.claims[settlementId]
    self.claims[settlementId] = nil
    self:_record({ kind = "settlement_released", factionId = old.factionId, settlementId = settlementId })
    return true, "released"
end

function FactionSovereignty:SetVassal(overlordId, vassalId, tributeRate)
    if overlordId == vassalId then return false, "self_vassal" end
    local okA, overlord = self:EnsureFaction(overlordId)
    local okB, vassal = self:EnsureFaction(vassalId)
    if not okA or not okB then return false, "invalid_faction" end
    if vassal.overlordId and self.factions[vassal.overlordId] then
        self.factions[vassal.overlordId].vassals[vassalId] = nil
    end
    vassal.overlordId = overlordId
    vassal.tributeRate = math.max(0, math.min(0.5, tonumber(tributeRate) or 0.1))
    overlord.vassals[vassalId] = true
    self:_record({ kind = "vassal_set", overlordId = overlordId, vassalId = vassalId, tributeRate = vassal.tributeRate })
    return true, "updated"
end

function FactionSovereignty:ReleaseVassal(vassalId)
    local vassal = self.factions[vassalId]
    if not vassal or not vassal.overlordId then return false, "not_vassal" end
    local overlordId = vassal.overlordId
    local overlord = self.factions[overlordId]
    if overlord then overlord.vassals[vassalId] = nil end
    vassal.overlordId = nil
    vassal.tributeRate = 0
    self:_record({ kind = "vassal_released", overlordId = overlordId, vassalId = vassalId })
    return true, "released"
end

function FactionSovereignty:GetFaction(id)
    local f = self.factions[id]
    if not f then return nil end
    return {
        id = f.id,
        name = f.name,
        rulerId = f.rulerId,
        treasuryRef = f.treasuryRef,
        overlordId = f.overlordId,
        tributeRate = f.tributeRate,
        vassalCount = countMap(f.vassals),
        reputation = f.reputation,
    }
end

function FactionSovereignty:GetClaim(settlementId)
    local c = self.claims[settlementId]
    if not c then return nil end
    return { settlementId = c.settlementId, factionId = c.factionId, legitimacy = c.legitimacy }
end

function FactionSovereignty:Snapshot()
    local factionCount, vassalCount = 0, 0
    for _, f in pairs(self.factions) do
        factionCount += 1
        if f.overlordId then vassalCount += 1 end
    end
    return {
        revision = self.revision,
        factionCount = factionCount,
        settlementClaimCount = countMap(self.claims),
        vassalCount = vassalCount,
        independentCount = factionCount - vassalCount,
        historyCount = #self.history,
    }
end

return FactionSovereignty

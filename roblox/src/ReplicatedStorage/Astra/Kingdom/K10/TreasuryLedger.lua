local TreasuryLedger = {}
TreasuryLedger.__index = TreasuryLedger

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function TreasuryLedger.new(initialBalance, maxHistory)
    return setmetatable({
        balance = math.max(0, initialBalance or 0),
        reserved = 0,
        reservations = {},
        seen = {},
        history = {},
        maxHistory = math.max(20, maxHistory or 200),
        revision = 0,
    }, TreasuryLedger)
end

function TreasuryLedger:_record(tx)
    self.revision += 1
    tx.revision = self.revision
    table.insert(self.history, tx)
    while #self.history > self.maxHistory do table.remove(self.history, 1) end
end

function TreasuryLedger:Available()
    return math.max(0, self.balance - self.reserved)
end

function TreasuryLedger:Credit(id, amount, reason)
    if self.seen[id] then return true, "duplicate" end
    if type(amount) ~= "number" or amount <= 0 then return false, "invalid_amount" end
    self.seen[id] = true
    self.balance += amount
    self:_record({ id = id, kind = "credit", amount = amount, reason = reason or "unspecified" })
    return true, "credited"
end

function TreasuryLedger:Debit(id, amount, reason)
    if self.seen[id] then return true, "duplicate" end
    if type(amount) ~= "number" or amount <= 0 then return false, "invalid_amount" end
    if amount > self:Available() then return false, "insufficient_available" end
    self.seen[id] = true
    self.balance -= amount
    self:_record({ id = id, kind = "debit", amount = amount, reason = reason or "unspecified" })
    return true, "debited"
end

function TreasuryLedger:Reserve(id, amount, reason)
    if self.reservations[id] then return true, "duplicate" end
    if type(amount) ~= "number" or amount <= 0 then return false, "invalid_amount" end
    if amount > self:Available() then return false, "insufficient_available" end
    self.reservations[id] = { amount = amount, reason = reason or "unspecified" }
    self.reserved += amount
    self:_record({ id = id, kind = "reserve", amount = amount, reason = reason or "unspecified" })
    return true, "reserved"
end

function TreasuryLedger:Release(id)
    local reservation = self.reservations[id]
    if not reservation then return false, "missing_reservation" end
    self.reserved = math.max(0, self.reserved - reservation.amount)
    self.reservations[id] = nil
    self:_record({ id = id, kind = "release", amount = reservation.amount, reason = reservation.reason })
    return true, "released"
end

function TreasuryLedger:CommitReserve(id, transactionId)
    local reservation = self.reservations[id]
    if not reservation then return false, "missing_reservation" end
    if self.seen[transactionId] then return true, "duplicate" end
    self.reserved = math.max(0, self.reserved - reservation.amount)
    self.balance = math.max(0, self.balance - reservation.amount)
    self.reservations[id] = nil
    self.seen[transactionId] = true
    self:_record({ id = transactionId, kind = "commit_reserve", reservationId = id, amount = reservation.amount, reason = reservation.reason })
    return true, "committed"
end

function TreasuryLedger:Snapshot()
    return {
        balance = self.balance,
        reserved = self.reserved,
        available = self:Available(),
        revision = self.revision,
        reservationCount = (function() local n = 0 for _ in pairs(self.reservations) do n += 1 end return n end)(),
        historyCount = #self.history,
    }
end

function TreasuryLedger:History()
    local out = {}
    for i, tx in ipairs(self.history) do out[i] = copy(tx) end
    return out
end

return TreasuryLedger

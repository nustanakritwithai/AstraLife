local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local TreasuryLedger = require(Kingdom.K10.TreasuryLedger)
local Verifier = require(Kingdom.K10.K10Verifier)

local scope = StateWriter.Scope("K10Treasury")
local ledger = TreasuryLedger.new(0, 200)
scope:SetAttribute("Version", "K10-0.1")
scope:SetAttribute("OwnsColonyStock", false)
scope:SetAttribute("ServerApi", true)

local apiFolder = script.Parent:FindFirstChild("K10TreasuryApi") or Instance.new("Folder")
apiFolder.Name = "K10TreasuryApi"
apiFolder.Parent = script.Parent

local function bind(name, fn)
    local old = apiFolder:FindFirstChild(name)
    if old then old:Destroy() end
    local b = Instance.new("BindableFunction")
    b.Name = name
    b.OnInvoke = fn
    b.Parent = apiFolder
end

local function publish()
    local before = SourceReader.ReadStocks()
    local snap = ledger:Snapshot()
    StateWriter.SetMany(scope, {
        Balance = math.floor(snap.balance * 100 + 0.5) / 100,
        Reserved = math.floor(snap.reserved * 100 + 0.5) / 100,
        Available = math.floor(snap.available * 100 + 0.5) / 100,
        Revision = snap.revision,
        ReservationCount = snap.reservationCount,
        HistoryCount = snap.historyCount,
    })
    Verifier.Verify(scope, before, SourceReader.ReadStocks(), snap)
    return snap
end

bind("Credit", function(id, amount, reason)
    local ok, code = ledger:Credit(id, amount, reason)
    publish()
    return ok, code
end)

bind("Debit", function(id, amount, reason)
    local ok, code = ledger:Debit(id, amount, reason)
    publish()
    return ok, code
end)

bind("Reserve", function(id, amount, reason)
    local ok, code = ledger:Reserve(id, amount, reason)
    publish()
    return ok, code
end)

bind("Release", function(id)
    local ok, code = ledger:Release(id)
    publish()
    return ok, code
end)

bind("CommitReserve", function(id, transactionId)
    local ok, code = ledger:CommitReserve(id, transactionId)
    publish()
    return ok, code
end)

bind("GetSnapshot", function()
    return ledger:Snapshot()
end)

publish()
print("[AstraKingdom] K10 Treasury Ledger attached")

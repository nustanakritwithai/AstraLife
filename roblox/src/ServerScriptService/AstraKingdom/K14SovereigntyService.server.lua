local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local Registry = require(Kingdom.K14.FactionSovereignty)
local Verifier = require(Kingdom.K14.K14Verifier)

local scope = StateWriter.Scope("K14Sovereignty")
local registry = Registry.new(200)
scope:SetAttribute("Version", "K14-0.1")
scope:SetAttribute("ProjectionOnly", true)
scope:SetAttribute("OwnsSettlementTruth", false)
scope:SetAttribute("OwnsAgentRoles", false)
scope:SetAttribute("OwnsStock", false)

local apiFolder = script.Parent:FindFirstChild("K14SovereigntyApi") or Instance.new("Folder")
apiFolder.Name = "K14SovereigntyApi"
apiFolder.Parent = script.Parent

local function bind(name, fn)
    local old = apiFolder:FindFirstChild(name)
    if old then old:Destroy() end
    local b = Instance.new("BindableFunction")
    b.Name = name
    b.OnInvoke = fn
    b.Parent = apiFolder
end

local function publish(before)
    local snapshot = registry:Snapshot()
    StateWriter.SetMany(scope, {
        Revision = snapshot.revision,
        FactionCount = snapshot.factionCount,
        SettlementClaimCount = snapshot.settlementClaimCount,
        VassalCount = snapshot.vassalCount,
        IndependentCount = snapshot.independentCount,
        HistoryCount = snapshot.historyCount,
    })
    Verifier.Verify(scope, before, Verifier.Capture(SourceReader), snapshot)
    return snapshot
end

bind("EnsureFaction", function(id, name)
    local before = Verifier.Capture(SourceReader)
    local ok, result = registry:EnsureFaction(id, name)
    publish(before)
    return ok, result
end)

bind("SetRuler", function(factionId, rulerId)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:SetRuler(factionId, rulerId)
    publish(before)
    return ok, code
end)

bind("SetTreasuryRef", function(factionId, treasuryRef)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:SetTreasuryRef(factionId, treasuryRef)
    publish(before)
    return ok, code
end)

bind("ClaimSettlement", function(factionId, settlementId, legitimacy)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:ClaimSettlement(factionId, settlementId, legitimacy)
    publish(before)
    return ok, code
end)

bind("ReleaseSettlement", function(settlementId)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:ReleaseSettlement(settlementId)
    publish(before)
    return ok, code
end)

bind("SetVassal", function(overlordId, vassalId, tributeRate)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:SetVassal(overlordId, vassalId, tributeRate)
    publish(before)
    return ok, code
end)

bind("ReleaseVassal", function(vassalId)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:ReleaseVassal(vassalId)
    publish(before)
    return ok, code
end)

bind("GetFaction", function(id) return registry:GetFaction(id) end)
bind("GetClaim", function(settlementId) return registry:GetClaim(settlementId) end)
bind("GetSnapshot", function() return registry:Snapshot() end)

publish(Verifier.Capture(SourceReader))
print("[AstraKingdom] K14 Faction/Sovereignty attached")

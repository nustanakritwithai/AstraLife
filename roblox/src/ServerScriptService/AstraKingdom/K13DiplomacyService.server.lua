local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local Diplomacy = require(Kingdom.K13.DiplomacyTreaties)
local Verifier = require(Kingdom.K13.K13Verifier)

local scope = StateWriter.Scope("K13Diplomacy")
local registry = Diplomacy.new(200)
scope:SetAttribute("Version", "K13-0.1")
scope:SetAttribute("OwnsFactionRelations", true)
scope:SetAttribute("OwnsAgentState", false)
scope:SetAttribute("OwnsStock", false)

local apiFolder = script.Parent:FindFirstChild("K13DiplomacyApi") or Instance.new("Folder")
apiFolder.Name = "K13DiplomacyApi"
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
    local typeCounts = snapshot.typeCounts or {}
    StateWriter.SetMany(scope, {
        Revision = snapshot.revision,
        TreatyCount = snapshot.treatyCount,
        ProposedCount = snapshot.proposedCount,
        ActiveCount = snapshot.activeCount,
        BrokenCount = snapshot.brokenCount,
        ExpiredCount = snapshot.expiredCount,
        TradeTreaties = typeCounts.trade or 0,
        Alliances = typeCounts.alliance or 0,
        PeaceTreaties = typeCounts.peace or 0,
        TributeTreaties = typeCounts.tribute or 0,
        Embargoes = typeCounts.embargo or 0,
        HistoryCount = snapshot.historyCount,
    })
    Verifier.Verify(scope, before, Verifier.Capture(SourceReader), snapshot)
    return snapshot
end

bind("Propose", function(id, treatyType, partyA, partyB, duration, terms)
    local before = Verifier.Capture(SourceReader)
    local tick = SourceReader.ReadCadence().agentTick
    local ok, code = registry:Propose(id, treatyType, partyA, partyB, tick, duration, terms)
    publish(before)
    return ok, code
end)

bind("Activate", function(id)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:Activate(id, SourceReader.ReadCadence().agentTick)
    publish(before)
    return ok, code
end)

bind("Break", function(id, reason)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:Break(id, SourceReader.ReadCadence().agentTick, reason)
    publish(before)
    return ok, code
end)

bind("GetTreaty", function(id) return registry:Get(id) end)
bind("GetSnapshot", function() return registry:Snapshot() end)

local function advance()
    local before = Verifier.Capture(SourceReader)
    registry:Advance(SourceReader.ReadCadence().agentTick)
    publish(before)
end

local state = SourceReader.AgentState()
if state then state:GetAttributeChangedSignal("WorldTick"):Connect(advance) end
publish(Verifier.Capture(SourceReader))

print("[AstraKingdom] K13 Diplomacy attached")

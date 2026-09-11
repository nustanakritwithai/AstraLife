local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local MerchantGuild = require(Kingdom.K12.MerchantGuild)
local Verifier = require(Kingdom.K12.K12Verifier)

local scope = StateWriter.Scope("K12MerchantGuild")
local registry = MerchantGuild.new(150)
scope:SetAttribute("Version", "K12-0.1")
scope:SetAttribute("OwnsAgents", false)
scope:SetAttribute("OwnsStock", false)
scope:SetAttribute("OwnsRoutes", false)

local apiFolder = script.Parent:FindFirstChild("K12MerchantGuildApi") or Instance.new("Folder")
apiFolder.Name = "K12MerchantGuildApi"
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
        GuildCount = snapshot.guildCount,
        WarehouseCount = snapshot.warehouseCount,
        MemberCount = snapshot.memberCount,
        GrossTradeValue = math.floor(snapshot.grossTradeValue * 100 + 0.5) / 100,
        RealizedProfit = math.floor(snapshot.realizedProfit * 100 + 0.5) / 100,
        CompletedTrades = snapshot.completedTrades,
        FailedTrades = snapshot.failedTrades,
        AverageReputation = math.floor(snapshot.averageReputation * 10 + 0.5) / 10,
        HistoryCount = snapshot.historyCount,
    })
    Verifier.Verify(scope, before, Verifier.Capture(SourceReader), snapshot)
    return snapshot
end

bind("EnsureGuild", function(guildId, name)
    local before = Verifier.Capture(SourceReader)
    local ok, result = registry:EnsureGuild(guildId, name)
    publish(before)
    return ok, result
end)

bind("RegisterWarehouse", function(guildId, settlementId, capacity)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:RegisterWarehouse(guildId, settlementId, capacity)
    publish(before)
    return ok, code
end)

bind("SetMember", function(guildId, agentId, active)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:SetMember(guildId, agentId, active)
    publish(before)
    return ok, code
end)

bind("RecordTrade", function(guildId, transactionId, grossValue, profit, success)
    local before = Verifier.Capture(SourceReader)
    local ok, code = registry:RecordTrade(guildId, transactionId, grossValue, profit, success)
    publish(before)
    return ok, code
end)

bind("GetSnapshot", function()
    return registry:Snapshot()
end)

publish(Verifier.Capture(SourceReader))
print("[AstraKingdom] K12 Merchant Guild attached")

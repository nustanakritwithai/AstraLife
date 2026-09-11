local MerchantGuild = {}
MerchantGuild.__index = MerchantGuild

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function countMap(map) local n = 0 for _ in pairs(map) do n += 1 end return n end

function MerchantGuild.new(maxHistory)
    return setmetatable({
        guilds = {},
        history = {},
        maxHistory = math.max(20, maxHistory or 150),
        revision = 0,
    }, MerchantGuild)
end

function MerchantGuild:_record(event)
    self.revision += 1
    event.revision = self.revision
    table.insert(self.history, event)
    while #self.history > self.maxHistory do table.remove(self.history, 1) end
end

function MerchantGuild:EnsureGuild(guildId, name)
    if type(guildId) ~= "string" or guildId == "" then return false, "invalid_guild_id" end
    local guild = self.guilds[guildId]
    if not guild then
        guild = {
            id = guildId,
            name = name or guildId,
            warehouses = {},
            members = {},
            completedTrades = 0,
            failedTrades = 0,
            grossTradeValue = 0,
            realizedProfit = 0,
            reputation = 50,
        }
        self.guilds[guildId] = guild
        self:_record({ kind = "guild_created", guildId = guildId })
    elseif name and name ~= "" then
        guild.name = name
    end
    return true, guild
end

function MerchantGuild:RegisterWarehouse(guildId, settlementId, capacity)
    local ok, guild = self:EnsureGuild(guildId)
    if not ok then return false, guild end
    if type(settlementId) ~= "string" or settlementId == "" then return false, "invalid_settlement_id" end
    local cap = math.max(0, tonumber(capacity) or 0)
    guild.warehouses[settlementId] = { settlementId = settlementId, capacity = cap }
    self:_record({ kind = "warehouse_registered", guildId = guildId, settlementId = settlementId, capacity = cap })
    return true, "registered"
end

function MerchantGuild:SetMember(guildId, agentId, active)
    local ok, guild = self:EnsureGuild(guildId)
    if not ok then return false, guild end
    if type(agentId) ~= "string" or agentId == "" then return false, "invalid_agent_id" end
    if active == false then guild.members[agentId] = nil else guild.members[agentId] = true end
    self:_record({ kind = active == false and "member_removed" or "member_added", guildId = guildId, agentId = agentId })
    return true, "updated"
end

function MerchantGuild:RecordTrade(guildId, transactionId, grossValue, profit, success)
    local ok, guild = self:EnsureGuild(guildId)
    if not ok then return false, guild end
    guild._seen = guild._seen or {}
    if guild._seen[transactionId] then return true, "duplicate" end
    guild._seen[transactionId] = true
    local gross = math.max(0, tonumber(grossValue) or 0)
    local realized = tonumber(profit) or 0
    guild.grossTradeValue += gross
    guild.realizedProfit += realized
    if success == false then guild.failedTrades += 1 else guild.completedTrades += 1 end
    local successCount = guild.completedTrades
    local attempts = successCount + guild.failedTrades
    local successRate = attempts > 0 and successCount / attempts or 1
    guild.reputation = clamp(35 + successRate * 45 + clamp(guild.realizedProfit / 500, -1, 1) * 20, 0, 100)
    self:_record({ kind = "trade_outcome", guildId = guildId, transactionId = transactionId, grossValue = gross, profit = realized, success = success ~= false })
    return true, "recorded"
end

function MerchantGuild:Snapshot()
    local guildCount, warehouseCount, memberCount = 0, 0, 0
    local gross, profit, completed, failed, reputation = 0, 0, 0, 0, 0
    for _, guild in pairs(self.guilds) do
        guildCount += 1
        warehouseCount += countMap(guild.warehouses)
        memberCount += countMap(guild.members)
        gross += guild.grossTradeValue
        profit += guild.realizedProfit
        completed += guild.completedTrades
        failed += guild.failedTrades
        reputation += guild.reputation
    end
    return {
        revision = self.revision,
        guildCount = guildCount,
        warehouseCount = warehouseCount,
        memberCount = memberCount,
        grossTradeValue = gross,
        realizedProfit = profit,
        completedTrades = completed,
        failedTrades = failed,
        averageReputation = guildCount > 0 and reputation / guildCount or 0,
        historyCount = #self.history,
    }
end

return MerchantGuild

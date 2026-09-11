local ResearchRegistry = {}
ResearchRegistry.__index = ResearchRegistry

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

function ResearchRegistry.new(catalog)
    return setmetatable({ catalog = catalog, profiles = {}, receipts = {} }, ResearchRegistry)
end

function ResearchRegistry:_profile(profileId)
    self.profiles[profileId] = self.profiles[profileId] or { unlocked = {}, revision = 0 }
    return self.profiles[profileId]
end

function ResearchRegistry:Quote(profileId, nodeId)
    local node = self.catalog.Get(nodeId)
    if not node then return nil, "unknown_research" end
    local profile = self:_profile(profileId)
    if profile.unlocked[nodeId] then return { alreadyUnlocked = true, scrapCost = 0, nodeId = nodeId } end
    local ok, reason = self.catalog.DependenciesMet(nodeId, profile.unlocked)
    if not ok then return nil, reason end
    return { nodeId = nodeId, scrapCost = node.scrapCost, tier = node.tier, unlocks = clone(node.unlocks) }
end

function ResearchRegistry:Commit(profileId, nodeId, transactionId, paymentReceipt)
    if type(transactionId) ~= "string" or transactionId == "" then return nil, "transaction_id_required" end
    if self.receipts[transactionId] then return clone(self.receipts[transactionId]), "duplicate" end
    if type(paymentReceipt) ~= "string" or paymentReceipt == "" then return nil, "payment_receipt_required" end
    local quote, reason = self:Quote(profileId, nodeId)
    if not quote then return nil, reason end
    local profile = self:_profile(profileId)
    profile.unlocked[nodeId] = true
    profile.revision += 1
    local result = { profileId = profileId, nodeId = nodeId, revision = profile.revision, paymentReceipt = paymentReceipt, unlocks = clone(quote.unlocks or {}) }
    self.receipts[transactionId] = result
    return clone(result), "committed"
end

function ResearchRegistry:Snapshot(profileId)
    return clone(self:_profile(profileId))
end

return ResearchRegistry

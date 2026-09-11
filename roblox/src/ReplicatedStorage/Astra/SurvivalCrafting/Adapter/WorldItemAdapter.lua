local GatheringContracts = require(script.Parent.Parent.S2.GatheringContracts)

local WorldItemAdapter = {}
WorldItemAdapter.Provenance = "LivingWorld"

local function firstInvalidField(receipt)
    if type(receipt.transactionId) ~= "string" or receipt.transactionId == "" then return "transactionId" end
    if type(receipt.actorId) ~= "string" or receipt.actorId == "" then return "actorId" end
    if type(receipt.worldTick) ~= "number" then return "worldTick" end
    if type(receipt.cellKey) ~= "string" or receipt.cellKey == "" then return "cellKey" end
    if type(receipt.worldResourceType) ~= "string" or receipt.worldResourceType == "" then return "worldResourceType" end
    if type(receipt.sourceKind) ~= "string" or receipt.sourceKind == "" then return "sourceKind" end
    if type(receipt.actualWithdrawn) ~= "number" then return "actualWithdrawn" end
    if type(receipt.toolClass) ~= "string" or receipt.toolClass == "" then return "toolClass" end
    if type(receipt.toolTier) ~= "number" then return "toolTier" end
    return nil
end

function WorldItemAdapter.BuildReceipt(fields)
    if type(fields) ~= "table" then return nil, "invalid_receipt:fields" end
    local invalid = firstInvalidField(fields)
    if invalid then return nil, "invalid_receipt:" .. invalid end
    if fields.actualWithdrawn <= 0 then return nil, "invalid_receipt:actualWithdrawn" end
    return {
        transactionId = fields.transactionId,
        actorId = fields.actorId,
        worldTick = fields.worldTick,
        cellKey = fields.cellKey,
        worldResourceType = fields.worldResourceType,
        sourceKind = fields.sourceKind,
        actualWithdrawn = fields.actualWithdrawn,
        toolClass = fields.toolClass,
        toolTier = fields.toolTier,
        provenance = WorldItemAdapter.Provenance,
    }
end

function WorldItemAdapter.ValidateReceipt(receipt)
    if type(receipt) ~= "table" then return false, "invalid_receipt:receipt" end
    if receipt.provenance ~= WorldItemAdapter.Provenance then return false, "wrong_provenance" end
    local invalid = firstInvalidField(receipt)
    if invalid then return false, "invalid_receipt:" .. invalid end
    if receipt.actualWithdrawn <= 0 then return false, "nothing_withdrawn" end
    return true
end

function WorldItemAdapter.Convert(receipt, options)
    local ok, reason = WorldItemAdapter.ValidateReceipt(receipt)
    if not ok then return nil, reason end
    options = options or {}
    local tool = options.tool or { class = receipt.toolClass, tier = receipt.toolTier, efficiency = 1 }
    local worldUnitsPerAction = options.worldUnitsPerAction or 1
    local full, estimateReason = GatheringContracts.EstimateYield(receipt.sourceKind, tool, 1)
    if not full then return nil, estimateReason end
    if type(worldUnitsPerAction) ~= "number" or worldUnitsPerAction <= 0 then return nil, "invalid_world_basis" end
    -- A withdrawal can cover several S2 actions (0.15 water at 0.05 per action is
    -- 3 actions); yields scale linearly with whole actions and a partial action is
    -- floored, so no partial amount ever exceeds the single-action policy yield.
    local fraction = receipt.actualWithdrawn / worldUnitsPerAction
    local yields = {}
    for itemId, amount in pairs(full) do
        yields[itemId] = math.floor(amount * fraction + 1e-9)
    end
    local copy = {}
    for key, value in pairs(receipt) do copy[key] = value end
    copy.yieldFraction = fraction
    copy.yields = yields
    return yields, copy
end

function WorldItemAdapter.ResolveSourceKind(worldResourceType, context)
    local source = type(context) == "table" and context.source or nil
    if worldResourceType == "Wood" then
        if source == "dead_tree" then return "DeadTree" end
        return "Tree"
    end
    if worldResourceType == "Stone" then return "Rock" end
    if worldResourceType == "Food" and source == "forage" then return "ForageBush" end
    if worldResourceType == "Water" then return "WaterSource" end
    return nil, "unmapped_resource"
end

return WorldItemAdapter

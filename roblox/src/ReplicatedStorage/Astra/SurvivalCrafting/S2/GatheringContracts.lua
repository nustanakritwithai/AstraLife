local GatheringContracts = {}

local contracts = {
    Tree = { toolClass = "axe", minTier = 0, hardness = 1.0, yields = { Log = 3, Stick = 1 } },
    DeadTree = { toolClass = "axe", minTier = 0, hardness = 0.8, yields = { Log = 2, Stick = 2 } },
    Rock = { toolClass = "pickaxe", minTier = 0, hardness = 1.2, yields = { StoneChunk = 3, Flint = 1 } },
    IronVein = { toolClass = "pickaxe", minTier = 1, hardness = 2.0, yields = { IronOre = 3, StoneChunk = 1 } },
    SulfurVein = { toolClass = "pickaxe", minTier = 1, hardness = 2.2, yields = { SulfurOre = 3, StoneChunk = 1 } },
    FiberPlant = { toolClass = "hand", minTier = 0, hardness = 0.2, yields = { Fiber = 4 } },
    AnimalCarcass = { toolClass = "knife", minTier = 1, hardness = 0.7, yields = { RawMeat = 3, Leather = 2 } },
    SalvagePile = { toolClass = "hand", minTier = 0, hardness = 0.5, yields = { Scrap = 3, Gear = 1 } },
    -- I2: water and forage source semantics so the WorldGatherReceipt adapter
    -- can convert W water/forage withdrawals without fabricating item kinds.
    WaterSource = { toolClass = "hand", minTier = 0, hardness = 0.1, yields = { FreshWater = 1 } },
    ForageBush = { toolClass = "hand", minTier = 0, hardness = 0.15, yields = { ForageGreens = 3 } },
}

function GatheringContracts.Get(sourceKind)
    return contracts[sourceKind]
end

function GatheringContracts.All()
    return contracts
end

function GatheringContracts.CanGather(sourceKind, tool)
    local contract = contracts[sourceKind]
    if not contract then return false, "unknown_source" end
    tool = tool or { class = "hand", tier = 0, efficiency = 1 }
    if contract.toolClass ~= "hand" and tool.class ~= contract.toolClass then
        return false, "wrong_tool_class"
    end
    if (tool.tier or 0) < contract.minTier then return false, "tool_tier_too_low" end
    return true
end

function GatheringContracts.EstimateYield(sourceKind, tool, remainingFraction)
    local ok, reason = GatheringContracts.CanGather(sourceKind, tool)
    if not ok then return nil, reason end
    local contract = contracts[sourceKind]
    local efficiency = math.max(0.25, tool and tool.efficiency or 1)
    local remaining = math.clamp(remainingFraction == nil and 1 or remainingFraction, 0, 1)
    local out = {}
    for itemId, amount in pairs(contract.yields) do
        out[itemId] = math.max(0, math.floor(amount * efficiency * remaining + 0.5))
    end
    return out
end

return GatheringContracts

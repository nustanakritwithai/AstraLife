local ToolCatalog = {}

local tools = {
    Hand = { class = "hand", tier = 0, efficiency = 0.35, maxDurability = math.huge, durabilityCost = 0 },
    WoodAxe = { class = "axe", tier = 1, efficiency = 0.75, maxDurability = 80, durabilityCost = 1.0, repair = { Log = 2 } },
    StoneAxe = { class = "axe", tier = 2, efficiency = 1.05, maxDurability = 160, durabilityCost = 0.9, repair = { StoneChunk = 2, Stick = 1 } },
    StonePickaxe = { class = "pickaxe", tier = 1, efficiency = 1.0, maxDurability = 180, durabilityCost = 1.0, repair = { StoneChunk = 2, Stick = 1 } },
    MetalPickaxe = { class = "pickaxe", tier = 2, efficiency = 1.55, maxDurability = 420, durabilityCost = 0.65, repair = { MetalFragment = 3, Stick = 1 } },
    Hammer = { class = "hammer", tier = 2, efficiency = 1.0, maxDurability = 300, durabilityCost = 0.75, repair = { MetalFragment = 2, Stick = 1 } },
    Knife = { class = "knife", tier = 2, efficiency = 1.35, maxDurability = 220, durabilityCost = 0.8, repair = { MetalFragment = 2 } },
}

function ToolCatalog.Get(id)
    return tools[id]
end

function ToolCatalog.All()
    return tools
end

function ToolCatalog.Describe(id, durability)
    local tool = tools[id]
    if not tool then return nil end
    local current = durability == nil and tool.maxDurability or durability
    local ratio = tool.maxDurability == math.huge and 1 or math.clamp(current / tool.maxDurability, 0, 1)
    return {
        id = id,
        class = tool.class,
        tier = tool.tier,
        efficiency = tool.efficiency * (0.5 + 0.5 * ratio),
        durability = current,
        maxDurability = tool.maxDurability,
        condition = ratio,
        durabilityCost = tool.durabilityCost,
    }
end

function ToolCatalog.EstimateDurabilityAfterUse(id, durability, workUnits)
    local tool = tools[id]
    if not tool then return nil, "unknown_tool" end
    if tool.maxDurability == math.huge then return math.huge end
    local current = durability == nil and tool.maxDurability or durability
    return math.max(0, current - math.max(0, workUnits or 1) * tool.durabilityCost)
end

return ToolCatalog

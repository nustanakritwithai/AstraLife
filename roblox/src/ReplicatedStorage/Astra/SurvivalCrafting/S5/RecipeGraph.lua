local RecipeGraph = {}

local recipes = {
    plank_from_log = { inputs = { Log = 1 }, outputs = { Plank = 2 }, station = "hand", craftTicks = 2, researchTier = 0 },
    sticks_from_log = { inputs = { Log = 1 }, outputs = { Stick = 4 }, station = "hand", craftTicks = 1, researchTier = 0 },
    cloth_from_fiber = { inputs = { Fiber = 5 }, outputs = { Cloth = 2 }, station = "hand", craftTicks = 2, researchTier = 0 },
    rope_from_fiber = { inputs = { Fiber = 6 }, outputs = { Rope = 1 }, station = "hand", craftTicks = 2, researchTier = 0 },
    charcoal_from_log = { inputs = { Log = 2 }, outputs = { Charcoal = 2 }, station = "Campfire", craftTicks = 5, researchTier = 0 },
    cooked_meat = { inputs = { RawMeat = 1, Charcoal = 1 }, outputs = { CookedMeat = 1 }, station = "Campfire", craftTicks = 4, researchTier = 0 },
    iron_smelting = { inputs = { IronOre = 2, Charcoal = 1 }, outputs = { MetalFragment = 2 }, station = "Furnace", craftTicks = 6, researchTier = 1 },
    sulfur_smelting = { inputs = { SulfurOre = 2, Charcoal = 1 }, outputs = { Sulfur = 2 }, station = "Furnace", craftTicks = 6, researchTier = 1 },
    nails = { inputs = { MetalFragment = 1 }, outputs = { Nail = 8 }, station = "Anvil", craftTicks = 3, researchTier = 1 },
    gear = { inputs = { MetalFragment = 4 }, outputs = { Gear = 1 }, station = "Workbench", craftTicks = 6, researchTier = 2 },
    wood_axe = { inputs = { Log = 2, Stick = 2, Rope = 1 }, outputs = { WoodAxe = 1 }, station = "hand", craftTicks = 4, researchTier = 0 },
    stone_axe = { inputs = { StoneChunk = 3, Stick = 2, Rope = 1 }, outputs = { StoneAxe = 1 }, station = "hand", craftTicks = 5, researchTier = 0 },
    stone_pickaxe = { inputs = { StoneChunk = 4, Stick = 2, Rope = 1 }, outputs = { StonePickaxe = 1 }, station = "hand", craftTicks = 5, researchTier = 0 },
    metal_pickaxe = { inputs = { MetalFragment = 8, Stick = 2, Rope = 1 }, outputs = { MetalPickaxe = 1 }, station = "Workbench", craftTicks = 10, researchTier = 2 },
    hammer = { inputs = { MetalFragment = 5, Stick = 2 }, outputs = { Hammer = 1 }, station = "Workbench", craftTicks = 7, researchTier = 1 },
    knife = { inputs = { MetalFragment = 4, Cloth = 1 }, outputs = { Knife = 1 }, station = "Anvil", craftTicks = 6, researchTier = 1 },
    campfire_kit = { inputs = { StoneChunk = 8, Log = 4 }, outputs = { CampfireKit = 1 }, station = "hand", craftTicks = 6, researchTier = 0 },
    furnace_kit = { inputs = { StoneChunk = 20, Log = 8, MetalFragment = 4 }, outputs = { FurnaceKit = 1 }, station = "hand", craftTicks = 14, researchTier = 1 },
    workbench_kit = { inputs = { Plank = 20, MetalFragment = 10, Gear = 2 }, outputs = { WorkbenchKit = 1 }, station = "hand", craftTicks = 16, researchTier = 1 },
    anvil_kit = { inputs = { StoneChunk = 15, MetalFragment = 20 }, outputs = { AnvilKit = 1 }, station = "Workbench", craftTicks = 18, researchTier = 2 },
    wood_foundation = { inputs = { Plank = 8, Nail = 4 }, outputs = { WoodFoundation = 1 }, station = "Workbench", craftTicks = 5, researchTier = 0 },
    wood_wall = { inputs = { Plank = 6, Nail = 3 }, outputs = { WoodWall = 1 }, station = "Workbench", craftTicks = 4, researchTier = 0 },
    wood_doorframe = { inputs = { Plank = 6, Nail = 4 }, outputs = { WoodDoorFrame = 1 }, station = "Workbench", craftTicks = 4, researchTier = 0 },
    wood_roof = { inputs = { Plank = 7, Nail = 4 }, outputs = { WoodRoof = 1 }, station = "Workbench", craftTicks = 5, researchTier = 0 },
    stone_foundation = { inputs = { StoneChunk = 18, MetalFragment = 2 }, outputs = { StoneFoundation = 1 }, station = "Workbench", craftTicks = 8, researchTier = 1 },
    stone_wall = { inputs = { StoneChunk = 14, MetalFragment = 2 }, outputs = { StoneWall = 1 }, station = "Workbench", craftTicks = 7, researchTier = 1 },
    metal_wall = { inputs = { MetalFragment = 20, Nail = 8 }, outputs = { MetalWall = 1 }, station = "Workbench", craftTicks = 10, researchTier = 2 },
}

function RecipeGraph.Get(id)
    return recipes[id]
end

function RecipeGraph.All()
    return recipes
end

function RecipeGraph.Producers(itemId)
    local out = {}
    for id, recipe in pairs(recipes) do
        if (recipe.outputs or {})[itemId] then table.insert(out, id) end
    end
    table.sort(out)
    return out
end

function RecipeGraph.CanUse(id, station, researchTier)
    local recipe = recipes[id]
    if not recipe then return false, "unknown_recipe" end
    if recipe.station ~= "hand" and recipe.station ~= station then return false, "wrong_station" end
    if (researchTier or 0) < (recipe.researchTier or 0) then return false, "research_locked" end
    return true
end

return RecipeGraph

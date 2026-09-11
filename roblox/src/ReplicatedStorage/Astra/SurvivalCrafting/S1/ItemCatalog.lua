local ItemCatalog = {}

local items = {
    Log = { kind = "raw", maxStack = 50, mass = 2.0, tags = {"wood", "natural"} },
    Plank = { kind = "processed", maxStack = 100, mass = 1.0, tags = {"wood", "building"} },
    Stick = { kind = "component", maxStack = 100, mass = 0.2, tags = {"wood", "component"} },
    StoneChunk = { kind = "raw", maxStack = 50, mass = 2.5, tags = {"stone", "natural"} },
    Flint = { kind = "component", maxStack = 100, mass = 0.2, tags = {"stone", "component"} },
    Fiber = { kind = "raw", maxStack = 100, mass = 0.1, tags = {"plant", "textile"} },
    Cloth = { kind = "processed", maxStack = 100, mass = 0.1, tags = {"textile", "component"} },
    Rope = { kind = "component", maxStack = 50, mass = 0.3, tags = {"textile", "component"} },
    Leather = { kind = "processed", maxStack = 50, mass = 0.5, tags = {"animal", "component"} },
    RawMeat = { kind = "food_raw", maxStack = 20, mass = 0.5, tags = {"food", "animal"} },
    CookedMeat = { kind = "food", maxStack = 20, mass = 0.45, tags = {"food", "cooked"} },
    IronOre = { kind = "ore", maxStack = 50, mass = 3.0, tags = {"metal", "ore"} },
    SulfurOre = { kind = "ore", maxStack = 50, mass = 3.0, tags = {"mineral", "ore"} },
    MetalFragment = { kind = "processed", maxStack = 100, mass = 1.0, tags = {"metal", "component"} },
    Sulfur = { kind = "processed", maxStack = 100, mass = 0.8, tags = {"mineral", "component"} },
    Charcoal = { kind = "processed", maxStack = 100, mass = 0.3, tags = {"fuel", "carbon"} },
    Scrap = { kind = "currency", maxStack = 500, mass = 0.1, tags = {"research", "trade"} },
    Nail = { kind = "component", maxStack = 200, mass = 0.05, tags = {"metal", "building"} },
    Gear = { kind = "component", maxStack = 50, mass = 0.5, tags = {"metal", "machine"} },
    WoodAxe = { kind = "tool", maxStack = 1, mass = 2.0, durability = 80, tags = {"tool", "axe", "wood"} },
    StoneAxe = { kind = "tool", maxStack = 1, mass = 2.2, durability = 160, tags = {"tool", "axe", "stone"} },
    StonePickaxe = { kind = "tool", maxStack = 1, mass = 2.5, durability = 180, tags = {"tool", "pickaxe", "stone"} },
    MetalPickaxe = { kind = "tool", maxStack = 1, mass = 2.5, durability = 420, tags = {"tool", "pickaxe", "metal"} },
    Hammer = { kind = "tool", maxStack = 1, mass = 1.5, durability = 300, tags = {"tool", "building"} },
    Knife = { kind = "tool", maxStack = 1, mass = 0.8, durability = 220, tags = {"tool", "harvest", "metal"} },
    CampfireKit = { kind = "station_kit", maxStack = 5, mass = 4.0, tags = {"station", "cooking"} },
    FurnaceKit = { kind = "station_kit", maxStack = 2, mass = 12.0, tags = {"station", "smelting"} },
    WorkbenchKit = { kind = "station_kit", maxStack = 1, mass = 15.0, tags = {"station", "crafting", "research"} },
    AnvilKit = { kind = "station_kit", maxStack = 1, mass = 18.0, tags = {"station", "metalworking"} },
    WoodFoundation = { kind = "build_part", maxStack = 20, mass = 8.0, tags = {"building", "foundation", "wood"} },
    WoodWall = { kind = "build_part", maxStack = 30, mass = 5.0, tags = {"building", "wall", "wood"} },
    WoodDoorFrame = { kind = "build_part", maxStack = 20, mass = 5.0, tags = {"building", "doorframe", "wood"} },
    WoodRoof = { kind = "build_part", maxStack = 20, mass = 6.0, tags = {"building", "roof", "wood"} },
    StoneFoundation = { kind = "build_part", maxStack = 20, mass = 15.0, tags = {"building", "foundation", "stone"} },
    StoneWall = { kind = "build_part", maxStack = 30, mass = 10.0, tags = {"building", "wall", "stone"} },
    MetalWall = { kind = "build_part", maxStack = 20, mass = 12.0, tags = {"building", "wall", "metal"} },
}

function ItemCatalog.Get(id)
    return items[id]
end

function ItemCatalog.Exists(id)
    return items[id] ~= nil
end

function ItemCatalog.All()
    return items
end

function ItemCatalog.Count()
    local count = 0
    for _ in pairs(items) do count += 1 end
    return count
end

function ItemCatalog.HasTag(id, tag)
    local item = items[id]
    if not item then return false end
    for _, value in ipairs(item.tags or {}) do
        if value == tag then return true end
    end
    return false
end

return ItemCatalog

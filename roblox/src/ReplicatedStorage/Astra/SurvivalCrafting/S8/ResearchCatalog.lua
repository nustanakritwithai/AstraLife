local ResearchCatalog = {}

local nodes = {
    furnace = { tier = 1, scrapCost = 20, requires = {}, unlocks = {"furnace_kit", "iron_smelting", "sulfur_smelting"} },
    workbench = { tier = 1, scrapCost = 25, requires = {}, unlocks = {"workbench_kit", "hammer", "wood_foundation", "wood_wall", "wood_doorframe", "wood_roof"} },
    metal_tools = { tier = 2, scrapCost = 35, requires = {"furnace", "workbench"}, unlocks = {"metal_pickaxe", "knife"} },
    anvil = { tier = 2, scrapCost = 40, requires = {"furnace", "workbench"}, unlocks = {"anvil_kit", "nails"} },
    stone_building = { tier = 2, scrapCost = 30, requires = {"workbench"}, unlocks = {"stone_foundation", "stone_wall"} },
    metal_building = { tier = 3, scrapCost = 60, requires = {"anvil", "stone_building"}, unlocks = {"metal_wall", "gear"} },
}

function ResearchCatalog.Get(id) return nodes[id] end
function ResearchCatalog.All() return nodes end

function ResearchCatalog.DependenciesMet(id, unlocked)
    local node = nodes[id]
    if not node then return false, "unknown_research" end
    unlocked = unlocked or {}
    for _, requirement in ipairs(node.requires or {}) do
        if unlocked[requirement] ~= true then return false, "missing:" .. requirement end
    end
    return true
end

return ResearchCatalog

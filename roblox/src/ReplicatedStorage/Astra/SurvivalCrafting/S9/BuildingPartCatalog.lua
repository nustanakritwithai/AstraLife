local BuildingPartCatalog = {}

local parts = {
    WoodFoundation = { family = "foundation", tier = 1, maxHealth = 500, upkeepWeight = 1.0, size = Vector3.new(8, 1, 8), snapSockets = {"foundation_edge", "wall_base", "pillar"}, upgradeTo = "StoneFoundation", requiresFoundation = false },
    StoneFoundation = { family = "foundation", tier = 2, maxHealth = 1200, upkeepWeight = 1.6, size = Vector3.new(8, 1, 8), snapSockets = {"foundation_edge", "wall_base", "pillar"}, upgradeTo = nil, requiresFoundation = false },
    WoodWall = { family = "wall", tier = 1, maxHealth = 350, upkeepWeight = 0.7, size = Vector3.new(8, 6, 1), snapSockets = {"wall_side", "roof_edge"}, upgradeTo = "StoneWall", requiresFoundation = true },
    StoneWall = { family = "wall", tier = 2, maxHealth = 900, upkeepWeight = 1.2, size = Vector3.new(8, 6, 1), snapSockets = {"wall_side", "roof_edge"}, upgradeTo = "MetalWall", requiresFoundation = true },
    MetalWall = { family = "wall", tier = 3, maxHealth = 1800, upkeepWeight = 1.8, size = Vector3.new(8, 6, 1), snapSockets = {"wall_side", "roof_edge"}, upgradeTo = nil, requiresFoundation = true },
    WoodDoorFrame = { family = "doorframe", tier = 1, maxHealth = 320, upkeepWeight = 0.8, size = Vector3.new(8, 6, 1), snapSockets = {"wall_side", "door_mount", "roof_edge"}, upgradeTo = nil, requiresFoundation = true },
    WoodRoof = { family = "roof", tier = 1, maxHealth = 300, upkeepWeight = 0.8, size = Vector3.new(8, 1, 8), snapSockets = {"roof_edge"}, upgradeTo = nil, requiresFoundation = true },
}

local compatible = {
    foundation_edge = { foundation = true },
    wall_base = { wall = true, doorframe = true },
    wall_side = { wall = true, doorframe = true },
    roof_edge = { roof = true },
    door_mount = { door = true },
    pillar = { pillar = true },
}

function BuildingPartCatalog.Get(id) return parts[id] end
function BuildingPartCatalog.All() return parts end
function BuildingPartCatalog.NextUpgrade(id)
    local part = parts[id]
    return part and part.upgradeTo or nil
end
function BuildingPartCatalog.CanSnap(parentId, childId, socketType)
    local parent, child = parts[parentId], parts[childId]
    if not parent or not child then return false, "unknown_part" end
    local hasSocket = false
    for _, socket in ipairs(parent.snapSockets or {}) do
        if socket == socketType then hasSocket = true break end
    end
    if not hasSocket then return false, "socket_missing" end
    local allowed = compatible[socketType]
    if not allowed or allowed[child.family] ~= true then return false, "incompatible_family" end
    return true
end

return BuildingPartCatalog

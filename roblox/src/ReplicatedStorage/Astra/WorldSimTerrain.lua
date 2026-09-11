local Grid = require(script.Parent.WorldSimGrid)
local Determinism = require(script.Parent.WorldSimDeterminism)

local WorldSimTerrain = {}

local TERRAIN = { "plain", "forest", "hill", "river", "marsh" }

local function terrainForCell(x, z, seed)
    local r = Determinism.Random01(seed or 1, string.format("terrain:%d:%d", x, z), 0)
    if r < 0.42 then return "plain" end
    if r < 0.66 then return "forest" end
    if r < 0.80 then return "hill" end
    if r < 0.92 then return "river" end
    return "marsh"
end

local function modifiers(terrain)
    if terrain == "forest" then
        return { movement = 0.88, gather = 1.12, safety = 0.92, defense = 1.12 }
    elseif terrain == "hill" then
        return { movement = 0.82, gather = 0.92, safety = 1.02, defense = 1.22 }
    elseif terrain == "river" then
        return { movement = 0.78, gather = 1.05, safety = 0.95, defense = 1.14 }
    elseif terrain == "marsh" then
        return { movement = 0.72, gather = 0.82, safety = 0.86, defense = 1.06 }
    end
    return { movement = 1.0, gather = 1.0, safety = 1.0, defense = 0.95 }
end

function WorldSimTerrain.Update(agentsFolder, terrainFolder, cellSize, seed)
    local counts = { plain = 0, forest = 0, hill = 0, river = 0, marsh = 0 }
    local agents = 0

    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local root = agent:FindFirstChild("HumanoidRootPart")
            if root then
                agents += 1
                local x, z = Grid.PositionToCell(root.Position, cellSize or 32)
                local terrain = terrainForCell(x, z, seed)
                local m = modifiers(terrain)
                counts[terrain] += 1
                agent:SetAttribute("TerrainType", terrain)
                agent:SetAttribute("TerrainMoveMultiplier", m.movement)
                agent:SetAttribute("TerrainGatherMultiplier", m.gather)
                agent:SetAttribute("TerrainSafetyMultiplier", m.safety)
                agent:SetAttribute("TerrainDefenseMultiplier", m.defense)
            end
        end
    end

    local dominant, dominantCount = "plain", -1
    for _, terrain in ipairs(TERRAIN) do
        local count = counts[terrain]
        terrainFolder:SetAttribute("Agents_" .. terrain, count)
        if count > dominantCount or (count == dominantCount and terrain < dominant) then
            dominant, dominantCount = terrain, count
        end
    end

    terrainFolder:SetAttribute("DominantTerrain", dominant)
    terrainFolder:SetAttribute("MappedAgentCount", agents)
    terrainFolder:SetAttribute("CellSize", cellSize or 32)
    return { counts = counts, dominant = dominant }
end

function WorldSimTerrain.ForPosition(position, cellSize, seed)
    local x, z = Grid.PositionToCell(position, cellSize or 32)
    return terrainForCell(x, z, seed)
end

return WorldSimTerrain

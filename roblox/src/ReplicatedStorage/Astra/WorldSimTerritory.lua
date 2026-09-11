local Grid = require(script.Parent.WorldSimGrid)

local WorldSimTerritory = {}

local function positionOf(instance)
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then
        local root = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart")
        return root and root.Position or nil
    end
    return nil
end

local function claim(claims, x, z, influence, source)
    local key = Grid.CellKey(x, z)
    local current = claims[key]
    if not current or influence > current.influence or (influence == current.influence and source < current.source) then
        claims[key] = { x = x, z = z, influence = influence, source = source }
    end
end

function WorldSimTerritory.Update(folders, territoryFolder, cellSize, basePosition)
    local claims = {}
    local size = cellSize or Grid.DEFAULT_CELL_SIZE
    local base = basePosition or Vector3.new(0, 0, 0)
    local bx, bz = Grid.PositionToCell(base, size)

    for _, cell in ipairs(Grid.Neighborhood(bx, bz, 1)) do
        local influence = cell.x == bx and cell.z == bz and 100 or 70
        claim(claims, cell.x, cell.z, influence, "ColonyBase")
    end

    local structureCount = 0
    for _, structure in ipairs(folders.structures:GetChildren()) do
        local position = positionOf(structure)
        if position then
            structureCount += 1
            local sx, sz = Grid.PositionToCell(position, size)
            claim(claims, sx, sz, 100, structure.Name)
            for _, cell in ipairs(Grid.Neighborhood(sx, sz, 1)) do
                if not (cell.x == sx and cell.z == sz) then
                    claim(claims, cell.x, cell.z, 55, structure.Name)
                end
            end
        end
    end

    local keys = {}
    local frontier = 0
    for key, data in pairs(claims) do
        table.insert(keys, key)
        if data.influence < 100 then frontier += 1 end
    end
    table.sort(keys)

    territoryFolder:SetAttribute("ClaimedCellCount", #keys)
    territoryFolder:SetAttribute("FrontierCellCount", frontier)
    territoryFolder:SetAttribute("StructureSources", structureCount)
    territoryFolder:SetAttribute("CellSize", size)
    territoryFolder:SetAttribute("ClaimedCells", table.concat(keys, ","))
    return claims
end

return WorldSimTerritory

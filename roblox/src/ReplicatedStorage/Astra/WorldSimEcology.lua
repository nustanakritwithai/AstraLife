local Grid = require(script.Parent.WorldSimGrid)

local WorldSimEcology = {}
local TYPES = { "Wood", "Stone", "Food", "Water" }

function WorldSimEcology.Update(resourcesFolder, marketFolder, ecologyFolder, cellSize)
    local counts = { Wood = 0, Stone = 0, Food = 0, Water = 0 }
    local cells = {}
    local activeTotal = 0

    for _, resource in ipairs(resourcesFolder:GetChildren()) do
        if resource:IsA("BasePart") and resource:GetAttribute("Active") ~= false then
            local resourceType = resource:GetAttribute("ResourceType") or "Wood"
            if counts[resourceType] ~= nil then counts[resourceType] += 1 end
            activeTotal += 1
            local key = Grid.PositionKey(resource.Position, cellSize or Grid.DEFAULT_CELL_SIZE)
            cells[key] = (cells[key] or 0) + 1
        end
    end

    local occupiedCells = 0
    local densestCell, densestCount = "None", 0
    for key, count in pairs(cells) do
        occupiedCells += 1
        if count > densestCount or (count == densestCount and key < densestCell) then
            densestCell, densestCount = key, count
        end
    end

    for _, resourceType in ipairs(TYPES) do
        local scarcity = marketFolder:GetAttribute("Scarcity_" .. resourceType) or 1
        local regenerationPressure = math.max(0, math.min(2, scarcity - counts[resourceType] * 0.08))
        ecologyFolder:SetAttribute("Active_" .. resourceType, counts[resourceType])
        ecologyFolder:SetAttribute("RegenerationPressure_" .. resourceType, math.floor(regenerationPressure * 1000 + 0.5) / 1000)
    end

    ecologyFolder:SetAttribute("ActiveResourceTotal", activeTotal)
    ecologyFolder:SetAttribute("OccupiedResourceCells", occupiedCells)
    ecologyFolder:SetAttribute("DensestResourceCell", densestCell)
    ecologyFolder:SetAttribute("DensestResourceCellCount", densestCount)

    return {
        counts = counts,
        activeTotal = activeTotal,
        occupiedCells = occupiedCells,
        densestCell = densestCell,
    }
end

return WorldSimEcology

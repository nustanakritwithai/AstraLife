local Grid = require(script.Parent.WorldSimGrid)

local WorldSimPopulation = {}

function WorldSimPopulation.Update(agentsFolder, populationFolder, cellSize)
    local total, critical, injured = 0, 0, 0
    local roles = {}
    local lod = { A_Full = 0, B_Reduced = 0, C_Abstract = 0, Unknown = 0 }
    local cells = {}

    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            total += 1
            local role = agent:GetAttribute("Role") or "Explorer"
            roles[role] = (roles[role] or 0) + 1
            local level = agent:GetAttribute("SimulationLOD") or "Unknown"
            lod[level] = (lod[level] or 0) + 1
            if agent:GetAttribute("SurvivalCritical") == true then critical += 1 end
            if (agent:GetAttribute("InjurySeverity") or 0) > 0 then injured += 1 end
            local root = agent:FindFirstChild("HumanoidRootPart")
            if root then
                local key = Grid.PositionKey(root.Position, cellSize or Grid.DEFAULT_CELL_SIZE)
                cells[key] = (cells[key] or 0) + 1
            end
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

    populationFolder:SetAttribute("Total", total)
    populationFolder:SetAttribute("Critical", critical)
    populationFolder:SetAttribute("Injured", injured)
    populationFolder:SetAttribute("OccupiedCells", occupiedCells)
    populationFolder:SetAttribute("DensestCell", densestCell)
    populationFolder:SetAttribute("DensestCellPopulation", densestCount)
    for role, count in pairs(roles) do populationFolder:SetAttribute("Role_" .. role, count) end
    for level, count in pairs(lod) do populationFolder:SetAttribute("LOD_" .. level, count) end

    return {
        total = total,
        critical = critical,
        injured = injured,
        occupiedCells = occupiedCells,
        densestCell = densestCell,
    }
end

return WorldSimPopulation

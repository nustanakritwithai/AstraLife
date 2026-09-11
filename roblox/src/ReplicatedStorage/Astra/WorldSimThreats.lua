local Grid = require(script.Parent.WorldSimGrid)

local WorldSimThreats = {}

local function rootOf(model)
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

function WorldSimThreats.Update(agentsFolder, worldState, threatsFolder, cellSize)
    local threatCount = 0
    local cells = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj:GetAttribute("IsThreat") == true then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local root = rootOf(obj)
            if root and (not humanoid or humanoid.Health > 0) then
                threatCount += 1
                local key = Grid.PositionKey(root.Position, cellSize or Grid.DEFAULT_CELL_SIZE)
                cells[key] = (cells[key] or 0) + 1
            end
        end
    end

    local population, unsafe = 0, 0
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            population += 1
            if (agent:GetAttribute("Safety") or 100) < 50 then unsafe += 1 end
        end
    end

    local dangerActive = worldState:GetAttribute("DangerActive") == true
    local unsafeRatio = unsafe / math.max(1, population)
    local pressure = math.min(1, threatCount * 0.25 + unsafeRatio * 0.45 + (dangerActive and 0.35 or 0))
    local hotCell, hotCount = "None", 0
    for key, count in pairs(cells) do
        if count > hotCount or (count == hotCount and key < hotCell) then
            hotCell, hotCount = key, count
        end
    end

    threatsFolder:SetAttribute("ThreatCount", threatCount)
    threatsFolder:SetAttribute("UnsafeAgentCount", unsafe)
    threatsFolder:SetAttribute("DangerActive", dangerActive)
    threatsFolder:SetAttribute("ThreatPressure", math.floor(pressure * 1000 + 0.5) / 1000)
    threatsFolder:SetAttribute("HotCell", hotCell)
    threatsFolder:SetAttribute("HotCellThreatCount", hotCount)

    return { count = threatCount, pressure = pressure, hotCell = hotCell }
end

return WorldSimThreats

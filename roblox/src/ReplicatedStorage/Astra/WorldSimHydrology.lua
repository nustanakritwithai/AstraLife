local Grid = require(script.Parent.WorldSimGrid)

local WorldSimHydrology = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimHydrology.Update(resourcesFolder, agentsFolder, worldState, hydrologyFolder, cellSize)
    local waterNodes = {}
    for _, resource in ipairs(resourcesFolder:GetChildren()) do
        if resource:IsA("BasePart")
            and resource:GetAttribute("Active") ~= false
            and resource:GetAttribute("ResourceType") == "Water"
        then
            table.insert(waterNodes, resource)
        end
    end
    table.sort(waterNodes, function(a, b) return a.Name < b.Name end)

    local weather = worldState:GetAttribute("Weather") or "Clear"
    local weatherRecharge = weather == "Rain" and 1 or weather == "Storm" and 0.85 or 0.25
    local accessTotal, agentCount = 0, 0

    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local root = agent:FindFirstChild("HumanoidRootPart")
            if root then
                agentCount += 1
                local nearest = math.huge
                for _, water in ipairs(waterNodes) do
                    nearest = math.min(nearest, (root.Position - water.Position).Magnitude)
                end
                local access = #waterNodes == 0 and 0 or clamp(1 - nearest / 160, 0, 1)
                accessTotal += access
                agent:SetAttribute("WaterAccess", math.floor(access * 1000 + 0.5) / 10)
                agent:SetAttribute("NearestWaterDistance", nearest == math.huge and -1 or math.floor(nearest * 10 + 0.5) / 10)
            end
        end
    end

    local waterCells = {}
    for _, water in ipairs(waterNodes) do
        waterCells[Grid.PositionKey(water.Position, cellSize or 32)] = true
    end
    local cellCount = 0
    for _ in pairs(waterCells) do cellCount += 1 end

    local averageAccess = accessTotal / math.max(1, agentCount)
    local droughtPressure = clamp((1 - averageAccess) * 0.7 + (1 - weatherRecharge) * 0.3, 0, 1)

    hydrologyFolder:SetAttribute("WaterNodeCount", #waterNodes)
    hydrologyFolder:SetAttribute("WaterCellCount", cellCount)
    hydrologyFolder:SetAttribute("AverageWaterAccess", math.floor(averageAccess * 1000 + 0.5) / 10)
    hydrologyFolder:SetAttribute("WeatherRecharge", math.floor(weatherRecharge * 1000 + 0.5) / 10)
    hydrologyFolder:SetAttribute("DroughtPressure", math.floor(droughtPressure * 1000 + 0.5) / 10)

    return { waterNodes = #waterNodes, averageAccess = averageAccess, droughtPressure = droughtPressure }
end

return WorldSimHydrology

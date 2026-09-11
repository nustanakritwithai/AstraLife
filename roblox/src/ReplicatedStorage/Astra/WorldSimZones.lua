local Grid = require(script.Parent.WorldSimGrid)

local WorldSimZones = {}

local function parseCells(text)
    local out = {}
    for key in string.gmatch(text or "", "[^,]+") do out[key] = true end
    return out
end

function WorldSimZones.Update(agentsFolder, territoryFolder, threatsFolder, zonesFolder, cellSize)
    local claimed = parseCells(territoryFolder:GetAttribute("ClaimedCells") or "")
    local hotCell = threatsFolder:GetAttribute("HotCell") or "None"
    local threatPressure = threatsFolder:GetAttribute("ThreatPressure") or 0
    local safeCount, cautionCount, dangerCount = 0, 0, 0

    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local root = agent:FindFirstChild("HumanoidRootPart")
            local cell = root and Grid.PositionKey(root.Position, cellSize or 32) or "unknown"
            local zone = "Neutral"
            if cell == hotCell and hotCell ~= "None" then
                zone = "Danger"
                dangerCount += 1
            elseif claimed[cell] and threatPressure < 0.65 then
                zone = "Safe"
                safeCount += 1
            elseif threatPressure >= 0.45 then
                zone = "Caution"
                cautionCount += 1
            end
            agent:SetAttribute("WorldZone", zone)
            agent:SetAttribute("WorldGridCell", cell)
        end
    end

    zonesFolder:SetAttribute("SafeAgentCount", safeCount)
    zonesFolder:SetAttribute("CautionAgentCount", cautionCount)
    zonesFolder:SetAttribute("DangerAgentCount", dangerCount)
    zonesFolder:SetAttribute("ThreatHotCell", hotCell)
    zonesFolder:SetAttribute("ThreatPressure", threatPressure)
    return { safe = safeCount, caution = cautionCount, danger = dangerCount }
end

return WorldSimZones

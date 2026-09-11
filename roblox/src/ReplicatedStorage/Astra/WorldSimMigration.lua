local Grid = require(script.Parent.WorldSimGrid)

local WorldSimMigration = {}

local BASE_FOOD_PRICE = 4

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimMigration.Update(agentsFolder, marketFolder, settlementFolder, threatsFolder, territoryFolder, cellSize)
    local foodPrice = marketFolder:GetAttribute("Price_Food") or BASE_FOOD_PRICE
    local unrest = (settlementFolder:GetAttribute("Unrest") or 0) / 100
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 0) / 100
    local threatPressure = threatsFolder:GetAttribute("ThreatPressure") or 0
    local claimedCells = territoryFolder:GetAttribute("ClaimedCells") or ""
    local pressureTotal = 0
    local candidates = 0

    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local hunger = (agent:GetAttribute("Hunger") or 100) / 100
            local thirst = (agent:GetAttribute("Thirst") or 100) / 100
            local safety = (agent:GetAttribute("Safety") or 100) / 100
            local loyalty = agent:GetAttribute("Trait_Loyalty") or 0.5
            local riskTolerance = agent:GetAttribute("Trait_RiskTolerance") or 0.5
            local root = agent:FindFirstChild("HumanoidRootPart")
            local cell = root and Grid.PositionKey(root.Position, cellSize or 32) or "unknown"

            local localBadness = math.max(0, foodPrice / BASE_FOOD_PRICE - 1) * 0.22
                + unrest * 0.22
                + threatPressure * 0.22
                + (1 - math.min(hunger, thirst)) * 0.2
                + (1 - safety) * 0.14
            local restraint = loyalty * 0.18 + (1 - riskTolerance) * 0.08 + prosperity * 0.1
            local pressure = clamp(localBadness - restraint, 0, 1)

            local intent = "Stay"
            if pressure >= 0.75 then intent = "LeaveArea"
            elseif pressure >= 0.5 then intent = "SeekRefuge"
            elseif pressure >= 0.3 then intent = "ConsiderMove" end

            agent:SetAttribute("MigrationPressure", math.floor(pressure * 1000 + 0.5) / 10)
            agent:SetAttribute("MigrationIntent", intent)
            agent:SetAttribute("MigrationOriginCell", cell)
            agent:SetAttribute("MigrationSuggested", pressure >= 0.5)
            agent:SetAttribute("MigrationSafeTerritory", claimedCells ~= "" and claimedCells or "None")

            pressureTotal += pressure
            if pressure >= 0.5 then candidates += 1 end
        end
    end

    local total = math.max(1, #agentsFolder:GetChildren())
    return {
        averagePressure = pressureTotal / total,
        candidateCount = candidates,
    }
end

return WorldSimMigration

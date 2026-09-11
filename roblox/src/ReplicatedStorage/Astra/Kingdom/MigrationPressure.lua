local MigrationPressure = {}

local BASE_FOOD_PRICE = 4

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function MigrationPressure.Update(folders, marketFolder, settlementFolder, migrationFolder)
    local foodPrice = marketFolder:GetAttribute("Price_Food") or BASE_FOOD_PRICE
    local unrest = (settlementFolder:GetAttribute("Unrest") or 0) / 100
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 0) / 100
    local pressureTotal, candidates, population = 0, 0, 0

    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            population += 1
            local hunger = (agent:GetAttribute("Hunger") or 100) / 100
            local thirst = (agent:GetAttribute("Thirst") or 100) / 100
            local safety = (agent:GetAttribute("Safety") or 100) / 100
            local localBadness = math.max(0, foodPrice / BASE_FOOD_PRICE - 1) * 0.28
                + unrest * 0.28
                + (1 - math.min(hunger, thirst)) * 0.24
                + (1 - safety) * 0.20
            local pressure = clamp(localBadness - prosperity * 0.12, 0, 1)
            pressureTotal += pressure
            if pressure >= 0.5 then candidates += 1 end
        end
    end

    local average = pressureTotal / math.max(1, population)
    migrationFolder:SetAttribute("AveragePressure", math.floor(average * 1000 + 0.5) / 10)
    migrationFolder:SetAttribute("CandidateCount", candidates)
    migrationFolder:SetAttribute("Population", population)
    migrationFolder:SetAttribute("SuggestedPolicy", average >= 0.7 and "EmergencyRelief"
        or average >= 0.45 and "ImproveConditions"
        or "Stable")
    return { average = average, candidates = candidates }
end

return MigrationPressure

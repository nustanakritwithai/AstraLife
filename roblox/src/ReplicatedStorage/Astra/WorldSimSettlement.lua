local WorldSimSettlement = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function countAgents(agentsFolder)
    local count, critical, safetyTotal, socialTotal, healthRatioTotal = 0, 0, 0, 0, 0
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local humanoid = agent:FindFirstChildOfClass("Humanoid")
            count += 1
            if agent:GetAttribute("SurvivalCritical") == true then critical += 1 end
            safetyTotal += agent:GetAttribute("Safety") or 100
            socialTotal += agent:GetAttribute("Social") or 100
            if humanoid and humanoid.MaxHealth > 0 then
                healthRatioTotal += humanoid.Health / humanoid.MaxHealth
            else
                healthRatioTotal += 1
            end
        end
    end
    return count, critical, safetyTotal, socialTotal, healthRatioTotal
end

function WorldSimSettlement.Update(folders, settlementFolder, marketFolder)
    local state = folders.state
    local population, critical, safetyTotal, socialTotal, healthRatioTotal = countAgents(folders.agents)
    local popDiv = math.max(1, population)
    local storageCapacity = math.max(1, state:GetAttribute("StorageCapacity") or 40)
    local stockTotal = state:GetAttribute("StockTotal") or 0
    local food = state:GetAttribute("Stock_Food") or 0
    local water = state:GetAttribute("Stock_Water") or 0
    local structureCount = #folders.structures:GetChildren()
    local dangerActive = state:GetAttribute("DangerActive") == true
    local foodDemand = marketFolder and (marketFolder:GetAttribute("Demand_Food") or 1) or 1
    local waterDemand = marketFolder and (marketFolder:GetAttribute("Demand_Water") or 1) or 1

    local foodSecurity = clamp(food / math.max(foodDemand, 1), 0, 1)
    local waterSecurity = clamp(water / math.max(waterDemand, 1), 0, 1)
    local storageHealth = clamp(stockTotal / storageCapacity, 0, 1)
    local averageSafety = safetyTotal / popDiv / 100
    local averageSocial = socialTotal / popDiv / 100
    local health = healthRatioTotal / popDiv
    local criticalRatio = critical / popDiv

    local prosperity = clamp(storageHealth * 0.35 + foodSecurity * 0.2 + waterSecurity * 0.2 + clamp(structureCount / 6, 0, 1) * 0.25, 0, 1)
    local danger = clamp((dangerActive and 0.55 or 0) + criticalRatio * 0.35 + (1 - averageSafety) * 0.3, 0, 1)
    local stability = clamp(averageSafety * 0.3 + averageSocial * 0.2 + health * 0.2 + prosperity * 0.3 - danger * 0.35, 0, 1)
    local unrest = clamp((1 - stability) * 0.65 + criticalRatio * 0.35, 0, 1)

    local values = {
        Population = population,
        CriticalPopulation = critical,
        FoodSecurity = foodSecurity * 100,
        WaterSecurity = waterSecurity * 100,
        Prosperity = prosperity * 100,
        Danger = danger * 100,
        Stability = stability * 100,
        Unrest = unrest * 100,
        AverageHealth = health * 100,
        StructureCount = structureCount,
    }

    for key, value in pairs(values) do
        if typeof(value) == "number" then value = math.floor(value * 10 + 0.5) / 10 end
        settlementFolder:SetAttribute(key, value)
    end

    return values
end

return WorldSimSettlement

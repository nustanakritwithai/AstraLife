local SettlementState = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function SettlementState.Update(folders, marketFolder, settlementFolder)
    local state = folders.state
    local population, critical, safetyTotal, socialTotal, healthTotal = 0, 0, 0, 0, 0
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            population += 1
            if agent:GetAttribute("SurvivalCritical") == true then critical += 1 end
            safetyTotal += agent:GetAttribute("Safety") or 100
            socialTotal += agent:GetAttribute("Social") or 100
            local humanoid = agent:FindFirstChildOfClass("Humanoid")
            healthTotal += humanoid and humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
        end
    end

    local popDiv = math.max(1, population)
    local food = state:GetAttribute("Stock_Food") or 0
    local water = state:GetAttribute("Stock_Water") or 0
    local foodDemand = marketFolder:GetAttribute("Demand_Food") or 1
    local waterDemand = marketFolder:GetAttribute("Demand_Water") or 1
    local totalStock = state:GetAttribute("StockTotal") or 0
    local capacity = math.max(1, state:GetAttribute("StorageCapacity") or 40)
    local structures = #folders.structures:GetChildren()
    local dangerActive = state:GetAttribute("DangerActive") == true

    local foodSecurity = clamp(food / math.max(1, foodDemand), 0, 1)
    local waterSecurity = clamp(water / math.max(1, waterDemand), 0, 1)
    local storageHealth = clamp(totalStock / capacity, 0, 1)
    local avgSafety = safetyTotal / popDiv / 100
    local avgSocial = socialTotal / popDiv / 100
    local avgHealth = healthTotal / popDiv
    local criticalRatio = critical / popDiv
    local prosperity = clamp(storageHealth * 0.35 + foodSecurity * 0.2 + waterSecurity * 0.2 + clamp(structures / 6, 0, 1) * 0.25, 0, 1)
    local danger = clamp((dangerActive and 0.55 or 0) + criticalRatio * 0.35 + (1 - avgSafety) * 0.3, 0, 1)
    local stability = clamp(avgSafety * 0.3 + avgSocial * 0.2 + avgHealth * 0.2 + prosperity * 0.3 - danger * 0.35, 0, 1)
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
        AverageHealth = avgHealth * 100,
        StructureCount = structures,
    }
    for key, value in pairs(values) do
        settlementFolder:SetAttribute(key, typeof(value) == "number" and math.floor(value * 10 + 0.5) / 10 or value)
    end
    return values
end

return SettlementState

local WorldSimEconomy = {}

local TYPES = { "Wood", "Stone", "Food", "Water" }
local BASE_PRICE = { Wood = 5, Stone = 7, Food = 4, Water = 3 }

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function countNeed(agentsFolder, attribute)
    local count = 0
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") and agent:GetAttribute(attribute) == true then
            count += 1
        end
    end
    return count
end

local function population(agentsFolder)
    local count = 0
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then count += 1 end
    end
    return count
end

local function buildMissing(state, resourceType)
    local required = state:GetAttribute("P3_Required_" .. resourceType) or 0
    local delivered = state:GetAttribute("P3_Delivered_" .. resourceType) or 0
    return math.max(0, required - delivered)
end

function WorldSimEconomy.Update(folders, marketFolder, climateFolder)
    local state = folders.state
    local pop = population(folders.agents)
    local needFood = countNeed(folders.agents, "NeedFood")
    local needWater = countNeed(folders.agents, "NeedWater")
    local danger = state:GetAttribute("DangerActive") == true and 1 or 0
    local capacity = math.max(1, state:GetAttribute("StorageCapacity") or 40)
    local total = state:GetAttribute("StockTotal") or 0
    local crowding = clamp(pop / 8, 0, 2)
    local cropMultiplier = climateFolder and (climateFolder:GetAttribute("CropMultiplier") or 1) or 1
    local volatilityTotal = 0
    local scarcityTotal = 0

    for _, resourceType in ipairs(TYPES) do
        local stock = state:GetAttribute("Stock_" .. resourceType) or 0
        local effectiveStock = stock
        if resourceType == "Food" then
            effectiveStock = stock * clamp(cropMultiplier, 0.25, 1.4)
        end

        local demand = math.max(1, pop * 0.75 + buildMissing(state, resourceType))
        if resourceType == "Food" then demand += needFood * 3 end
        if resourceType == "Water" then demand += needWater * 3 end
        if resourceType == "Wood" or resourceType == "Stone" then
            demand += (state:GetAttribute("ActiveBuildId") or "None") ~= "None" and 2 or 0
        end

        local scarcity = clamp(demand / math.max(effectiveStock, 1), 0.25, 6)
        local dangerMod = 1 + danger * 0.35
        local crowdFoodMod = resourceType == "Food" and (1 + math.max(0, crowding - 0.9) * 0.45) or 1
        local price = BASE_PRICE[resourceType] * (scarcity ^ 0.75) * dangerMod * crowdFoodMod
        price = clamp(price, BASE_PRICE[resourceType] * 0.3, BASE_PRICE[resourceType] * 6)

        local oldPrice = marketFolder:GetAttribute("Price_" .. resourceType) or price
        local volatility = math.abs(price - oldPrice) / math.max(oldPrice, 0.01)
        volatilityTotal += volatility
        scarcityTotal += scarcity

        marketFolder:SetAttribute("Demand_" .. resourceType, math.floor(demand * 100 + 0.5) / 100)
        marketFolder:SetAttribute("Scarcity_" .. resourceType, math.floor(scarcity * 1000 + 0.5) / 1000)
        marketFolder:SetAttribute("Price_" .. resourceType, math.floor(price * 100 + 0.5) / 100)
        marketFolder:SetAttribute("EffectiveStock_" .. resourceType, math.floor(effectiveStock * 100 + 0.5) / 100)
    end

    local storageHealth = clamp(total / capacity, 0, 1)
    local avgScarcity = scarcityTotal / #TYPES
    local avgVolatility = volatilityTotal / #TYPES
    local tradeHealth = clamp(100 - math.max(0, avgScarcity - 1) * 18 - danger * 22 + storageHealth * 15, 0, 100)

    marketFolder:SetAttribute("Population", pop)
    marketFolder:SetAttribute("Volatility", math.floor(avgVolatility * 1000 + 0.5) / 1000)
    marketFolder:SetAttribute("TradeHealth", math.floor(tradeHealth * 10 + 0.5) / 10)
    marketFolder:SetAttribute("FoodNeedCount", needFood)
    marketFolder:SetAttribute("WaterNeedCount", needWater)
    marketFolder:SetAttribute("CropMultiplier", math.floor(cropMultiplier * 1000 + 0.5) / 1000)

    return {
        population = pop,
        volatility = avgVolatility,
        tradeHealth = tradeHealth,
        averageScarcity = avgScarcity,
    }
end

return WorldSimEconomy

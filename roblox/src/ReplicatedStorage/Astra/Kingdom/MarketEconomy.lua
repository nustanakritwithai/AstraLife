local MarketEconomy = {}

local TYPES = { "Wood", "Stone", "Food", "Water" }
local BASE_PRICE = { Wood = 5, Stone = 7, Food = 4, Water = 3 }

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function countAgents(agentsFolder)
    local population, needFood, needWater = 0, 0, 0
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            population += 1
            if agent:GetAttribute("NeedFood") == true then needFood += 1 end
            if agent:GetAttribute("NeedWater") == true then needWater += 1 end
        end
    end
    return population, needFood, needWater
end

local function buildMissing(state, resourceType)
    local required = state:GetAttribute("P3_Required_" .. resourceType) or 0
    local delivered = state:GetAttribute("P3_Delivered_" .. resourceType) or 0
    return math.max(0, required - delivered)
end

function MarketEconomy.Update(folders, marketFolder)
    local state = folders.state
    local population, needFood, needWater = countAgents(folders.agents)
    local danger = state:GetAttribute("DangerActive") == true and 1 or 0
    local activeBuild = (state:GetAttribute("ActiveBuildId") or "None") ~= "None"
    local totalStock = state:GetAttribute("StockTotal") or 0
    local capacity = math.max(1, state:GetAttribute("StorageCapacity") or 40)
    local scarcityTotal, volatilityTotal = 0, 0

    for _, resourceType in ipairs(TYPES) do
        local stock = state:GetAttribute("Stock_" .. resourceType) or 0
        local demand = math.max(1, population * 0.75 + buildMissing(state, resourceType))
        if resourceType == "Food" then demand += needFood * 3 end
        if resourceType == "Water" then demand += needWater * 3 end
        if activeBuild and (resourceType == "Wood" or resourceType == "Stone") then demand += 2 end

        local scarcity = clamp(demand / math.max(stock, 1), 0.25, 6)
        local dangerMod = 1 + danger * 0.35
        local price = clamp(BASE_PRICE[resourceType] * (scarcity ^ 0.75) * dangerMod, BASE_PRICE[resourceType] * 0.3, BASE_PRICE[resourceType] * 6)
        local oldPrice = marketFolder:GetAttribute("Price_" .. resourceType) or price
        local volatility = math.abs(price - oldPrice) / math.max(oldPrice, 0.01)

        marketFolder:SetAttribute("Demand_" .. resourceType, math.floor(demand * 100 + 0.5) / 100)
        marketFolder:SetAttribute("Scarcity_" .. resourceType, math.floor(scarcity * 1000 + 0.5) / 1000)
        marketFolder:SetAttribute("Price_" .. resourceType, math.floor(price * 100 + 0.5) / 100)
        scarcityTotal += scarcity
        volatilityTotal += volatility
    end

    local storageHealth = clamp(totalStock / capacity, 0, 1)
    local avgScarcity = scarcityTotal / #TYPES
    local avgVolatility = volatilityTotal / #TYPES
    local tradeHealth = clamp(100 - math.max(0, avgScarcity - 1) * 18 - danger * 22 + storageHealth * 15, 0, 100)

    marketFolder:SetAttribute("Population", population)
    marketFolder:SetAttribute("FoodNeedCount", needFood)
    marketFolder:SetAttribute("WaterNeedCount", needWater)
    marketFolder:SetAttribute("Volatility", math.floor(avgVolatility * 1000 + 0.5) / 1000)
    marketFolder:SetAttribute("TradeHealth", math.floor(tradeHealth * 10 + 0.5) / 10)

    return { population = population, averageScarcity = avgScarcity, tradeHealth = tradeHealth }
end

return MarketEconomy

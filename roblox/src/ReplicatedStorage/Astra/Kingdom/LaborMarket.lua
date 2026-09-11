local LaborMarket = {}

local BASE_PRICE = { Wood = 5, Stone = 7, Food = 4, Water = 3 }
local PROFESSIONS = {
    farmer = "Food",
    woodcutter = "Wood",
    miner = "Stone",
    crafter = "Stone",
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function LaborMarket.Update(marketFolder, laborFolder)
    local bestProfession, bestPremium = "farmer", -1
    for profession, good in pairs(PROFESSIONS) do
        local ratio = (marketFolder:GetAttribute("Price_" .. good) or BASE_PRICE[good]) / BASE_PRICE[good]
        if profession == "crafter" then
            local woodRatio = (marketFolder:GetAttribute("Price_Wood") or BASE_PRICE.Wood) / BASE_PRICE.Wood
            ratio = (ratio + woodRatio) * 0.5
        end
        local target = clamp(1 + (ratio - 1) * 0.5, 1, 1.8)
        local key = "WagePremium_" .. profession
        local old = laborFolder:GetAttribute(key) or 1
        local premium = old * 0.7 + target * 0.3
        premium = math.floor(premium * 1000 + 0.5) / 1000
        laborFolder:SetAttribute(key, premium)
        if premium > bestPremium or (premium == bestPremium and profession < bestProfession) then
            bestProfession, bestPremium = profession, premium
        end
    end
    laborFolder:SetAttribute("HighestDemandProfession", bestProfession)
    laborFolder:SetAttribute("HighestWagePremium", bestPremium)
    return { profession = bestProfession, premium = bestPremium }
end

return LaborMarket

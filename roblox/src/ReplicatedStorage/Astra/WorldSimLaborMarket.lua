local WorldSimLaborMarket = {}

local BASE_PRICE = { Wood = 5, Stone = 7, Food = 4, Water = 3 }
local PROFESSIONS = {
    woodcutter = { good = "Wood", skill = "woodcutting" },
    miner = { good = "Stone", skill = "mining" },
    farmer = { good = "Food", skill = "farming" },
    crafter = { good = "Stone", skill = "crafting" },
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimLaborMarket.Update(agentsFolder, marketFolder, laborFolder)
    local bestProfession, bestPremium = "farmer", -1

    for profession, descriptor in pairs(PROFESSIONS) do
        local price = marketFolder:GetAttribute("Price_" .. descriptor.good) or BASE_PRICE[descriptor.good]
        local ratio = price / BASE_PRICE[descriptor.good]
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
        laborFolder:SetAttribute("Shortage_" .. descriptor.good, math.floor(ratio * 1000 + 0.5) / 1000)
        if premium > bestPremium or (premium == bestPremium and profession < bestProfession) then
            bestProfession, bestPremium = profession, premium
        end
    end

    laborFolder:SetAttribute("HighestDemandProfession", bestProfession)
    laborFolder:SetAttribute("HighestWagePremium", bestPremium)

    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local selectedProfession, selectedScore = bestProfession, -math.huge
            for profession, descriptor in pairs(PROFESSIONS) do
                local premium = laborFolder:GetAttribute("WagePremium_" .. profession) or 1
                local skill = agent:GetAttribute("Skill_" .. descriptor.skill) or 0
                local score = premium * (1 + skill * 0.12)
                if profession == "crafter" and agent:GetAttribute("Role") == "Builder" then score += 0.4 end
                if (profession == "woodcutter" or profession == "miner" or profession == "farmer") and agent:GetAttribute("Role") == "Gatherer" then score += 0.25 end
                if score > selectedScore or (score == selectedScore and profession < selectedProfession) then
                    selectedProfession, selectedScore = profession, score
                end
            end
            agent:SetAttribute("LaborBestProfession", selectedProfession)
            agent:SetAttribute("LaborOpportunityScore", math.floor(selectedScore * 1000 + 0.5) / 1000)
        end
    end

    return { profession = bestProfession, premium = bestPremium }
end

return WorldSimLaborMarket

local WorldSimRecruitment = {}

local TARGETS = {
    Scout = 0.25,
    Gatherer = 0.40,
    Builder = 0.25,
    Explorer = 0.10,
}

function WorldSimRecruitment.Update(populationFolder, settlementFolder, threatsFolder, laborFolder, recruitmentFolder)
    local total = populationFolder:GetAttribute("Total") or 0
    local threatPressure = threatsFolder:GetAttribute("ThreatPressure") or 0
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 0) / 100
    local highestLabor = laborFolder:GetAttribute("HighestDemandProfession") or "farmer"
    local topRole, topNeed = "Gatherer", -1

    for role, ratio in pairs(TARGETS) do
        local current = populationFolder:GetAttribute("Role_" .. role) or 0
        local target = math.max(role == "Explorer" and 0 or 1, math.ceil(total * ratio))
        local need = math.max(0, target - current)
        if role == "Scout" and threatPressure > 0.55 then need += 1 end
        if role == "Gatherer" and (highestLabor == "farmer" or highestLabor == "miner" or highestLabor == "woodcutter") then need += 1 end
        if role == "Builder" and prosperity < 0.45 then need += 1 end
        recruitmentFolder:SetAttribute("Need_" .. role, need)
        recruitmentFolder:SetAttribute("Target_" .. role, target)
        if need > topNeed or (need == topNeed and role < topRole) then
            topRole, topNeed = role, need
        end
    end

    local urgency = total == 0 and 1 or math.min(1, topNeed / math.max(1, total))
    recruitmentFolder:SetAttribute("HighestNeedRole", topRole)
    recruitmentFolder:SetAttribute("HighestNeedCount", topNeed)
    recruitmentFolder:SetAttribute("RecruitmentUrgency", math.floor(urgency * 1000 + 0.5) / 10)
    recruitmentFolder:SetAttribute("SuggestedOffer", topNeed > 0 and ("Recruit:" .. topRole) or "None")

    return { role = topRole, need = topNeed, urgency = urgency }
end

return WorldSimRecruitment

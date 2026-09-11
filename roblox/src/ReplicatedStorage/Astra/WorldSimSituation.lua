local WorldSimSituation = {}

function WorldSimSituation.Update(settlementFolder, threatsFolder, ecologyFolder, laborFolder, governanceFolder, situationFolder)
    local stability = (settlementFolder:GetAttribute("Stability") or 0) / 100
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 0) / 100
    local foodSecurity = (settlementFolder:GetAttribute("FoodSecurity") or 0) / 100
    local waterSecurity = (settlementFolder:GetAttribute("WaterSecurity") or 0) / 100
    local threatPressure = threatsFolder:GetAttribute("ThreatPressure") or 0
    local activeResources = ecologyFolder:GetAttribute("ActiveResourceTotal") or 0
    local reliefNeed = (governanceFolder:GetAttribute("ReliefNeed") or 0) / 100
    local securityNeed = (governanceFolder:GetAttribute("SecurityNeed") or 0) / 100
    local laborRole = laborFolder:GetAttribute("HighestDemandProfession") or "farmer"

    local situation = "Stable"
    local priority = 20
    if foodSecurity < 0.35 or waterSecurity < 0.35 or reliefNeed > 0.7 then
        situation, priority = "SurvivalCrisis", 100
    elseif threatPressure > 0.7 or securityNeed > 0.7 then
        situation, priority = "SecurityCrisis", 90
    elseif stability < 0.45 then
        situation, priority = "Instability", 75
    elseif activeResources < 4 then
        situation, priority = "ResourceShortage", 65
    elseif prosperity < 0.45 then
        situation, priority = "Recovery", 55
    elseif prosperity > 0.75 and stability > 0.7 then
        situation, priority = "ExpansionOpportunity", 45
    end

    situationFolder:SetAttribute("Situation", situation)
    situationFolder:SetAttribute("Priority", priority)
    situationFolder:SetAttribute("SuggestedFocus", situation == "SurvivalCrisis" and "FoodWater"
        or situation == "SecurityCrisis" and "Safety"
        or situation == "Instability" and "Stability"
        or situation == "ResourceShortage" and laborRole
        or situation == "Recovery" and "Production"
        or situation == "ExpansionOpportunity" and "Expansion"
        or "Maintain")
    situationFolder:SetAttribute("Stability", math.floor(stability * 1000 + 0.5) / 10)
    situationFolder:SetAttribute("Prosperity", math.floor(prosperity * 1000 + 0.5) / 10)
    situationFolder:SetAttribute("ThreatPressure", math.floor(threatPressure * 1000 + 0.5) / 10)
    return { situation = situation, priority = priority }
end

return WorldSimSituation

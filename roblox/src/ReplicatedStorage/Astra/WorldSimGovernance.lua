local WorldSimGovernance = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimGovernance.Update(settlementFolder, organizationFolder, threatsFolder, governanceFolder)
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 0) / 100
    local stability = (settlementFolder:GetAttribute("Stability") or 0) / 100
    local unrest = (settlementFolder:GetAttribute("Unrest") or 0) / 100
    local foodSecurity = (settlementFolder:GetAttribute("FoodSecurity") or 0) / 100
    local waterSecurity = (settlementFolder:GetAttribute("WaterSecurity") or 0) / 100
    local threatPressure = threatsFolder:GetAttribute("ThreatPressure") or 0
    local wealth = organizationFolder:GetAttribute("Wealth") or 0
    local reputation = (organizationFolder:GetAttribute("Reputation") or 0) / 100

    local taxTarget = clamp(0.08 + prosperity * 0.04 - unrest * 0.05, 0.03, 0.16)
    local securityNeed = clamp(threatPressure * 0.65 + (1 - stability) * 0.25 + unrest * 0.2, 0, 1)
    local reliefNeed = clamp((1 - foodSecurity) * 0.45 + (1 - waterSecurity) * 0.45 + unrest * 0.2, 0, 1)
    local legitimacy = clamp(stability * 0.35 + reputation * 0.25 + prosperity * 0.2 + foodSecurity * 0.1 + waterSecurity * 0.1 - unrest * 0.2, 0, 1)
    local projectedRevenue = wealth * taxTarget
    local securityBudget = projectedRevenue * clamp(0.2 + securityNeed * 0.45, 0.2, 0.65)
    local reliefBudget = projectedRevenue * clamp(0.1 + reliefNeed * 0.5, 0.1, 0.6)

    governanceFolder:SetAttribute("SuggestedTaxRate", math.floor(taxTarget * 10000 + 0.5) / 100)
    governanceFolder:SetAttribute("SecurityNeed", math.floor(securityNeed * 1000 + 0.5) / 10)
    governanceFolder:SetAttribute("ReliefNeed", math.floor(reliefNeed * 1000 + 0.5) / 10)
    governanceFolder:SetAttribute("Legitimacy", math.floor(legitimacy * 1000 + 0.5) / 10)
    governanceFolder:SetAttribute("ProjectedRevenue", math.floor(projectedRevenue * 100 + 0.5) / 100)
    governanceFolder:SetAttribute("SuggestedSecurityBudget", math.floor(securityBudget * 100 + 0.5) / 100)
    governanceFolder:SetAttribute("SuggestedReliefBudget", math.floor(reliefBudget * 100 + 0.5) / 100)
    governanceFolder:SetAttribute("Decision", reliefNeed > 0.65 and "EmergencyRelief" or securityNeed > 0.65 and "IncreaseSecurity" or unrest > 0.5 and "ReducePressure" or "Steady")

    return { taxRate = taxTarget, securityNeed = securityNeed, reliefNeed = reliefNeed, legitimacy = legitimacy }
end

return WorldSimGovernance

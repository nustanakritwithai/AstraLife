local Governance = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function Governance.Update(settlementFolder, organizationFolder, governanceFolder)
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 0) / 100
    local stability = (settlementFolder:GetAttribute("Stability") or 0) / 100
    local unrest = (settlementFolder:GetAttribute("Unrest") or 0) / 100
    local foodSecurity = (settlementFolder:GetAttribute("FoodSecurity") or 0) / 100
    local waterSecurity = (settlementFolder:GetAttribute("WaterSecurity") or 0) / 100
    local wealth = organizationFolder:GetAttribute("Wealth") or 0
    local reputation = (organizationFolder:GetAttribute("Reputation") or 50) / 100

    local taxRate = clamp(0.08 + prosperity * 0.04 - unrest * 0.05, 0.03, 0.16)
    local reliefNeed = clamp((1 - foodSecurity) * 0.45 + (1 - waterSecurity) * 0.45 + unrest * 0.2, 0, 1)
    local securityNeed = clamp((1 - stability) * 0.55 + unrest * 0.45, 0, 1)
    local legitimacy = clamp(stability * 0.35 + reputation * 0.25 + prosperity * 0.2 + foodSecurity * 0.1 + waterSecurity * 0.1 - unrest * 0.2, 0, 1)
    local projectedRevenue = wealth * taxRate

    governanceFolder:SetAttribute("SuggestedTaxRatePct", math.floor(taxRate * 10000 + 0.5) / 100)
    governanceFolder:SetAttribute("ReliefNeed", math.floor(reliefNeed * 1000 + 0.5) / 10)
    governanceFolder:SetAttribute("SecurityNeed", math.floor(securityNeed * 1000 + 0.5) / 10)
    governanceFolder:SetAttribute("Legitimacy", math.floor(legitimacy * 1000 + 0.5) / 10)
    governanceFolder:SetAttribute("ProjectedRevenue", math.floor(projectedRevenue * 100 + 0.5) / 100)
    governanceFolder:SetAttribute("Decision", reliefNeed > 0.65 and "EmergencyRelief"
        or securityNeed > 0.65 and "IncreaseSecurity"
        or unrest > 0.5 and "ReducePressure"
        or "Steady")

    return { taxRate = taxRate, reliefNeed = reliefNeed, securityNeed = securityNeed, legitimacy = legitimacy }
end

return Governance

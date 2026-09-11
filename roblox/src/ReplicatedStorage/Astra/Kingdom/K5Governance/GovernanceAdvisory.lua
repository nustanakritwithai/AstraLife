local GovernanceAdvisory = {}

GovernanceAdvisory.SchemaVersion = "K5.1"

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function round(value, places)
    local factor = 10 ^ (places or 2)
    return math.floor(value * factor + 0.5) / factor
end

local function normalizeBudget(securityWeight, reliefWeight, infrastructureWeight, adminWeight)
    local total = securityWeight + reliefWeight + infrastructureWeight + adminWeight
    return {
        security = securityWeight / total,
        relief = reliefWeight / total,
        infrastructure = infrastructureWeight / total,
        administration = adminWeight / total,
    }
end

function GovernanceAdvisory.Compute(source)
    local population = math.max(1, source.population.total or 0)
    local criticalRatio = (source.population.critical or 0) / population
    local safety = clamp((source.population.averageSafety or 100) / 100, 0, 1)
    local social = clamp((source.population.averageSocial or 100) / 100, 0, 1)
    local health = clamp(source.population.averageHealthRatio or 1, 0, 1)

    local foodSecurity = clamp((source.stocks.Food or 0) / math.max(population * 3, 1), 0, 1)
    local waterSecurity = clamp((source.stocks.Water or 0) / math.max(population * 3, 1), 0, 1)
    local reserveHealth = clamp((source.stocks.Total or 0) / math.max(source.stocks.Capacity or 0, 1), 0, 1)
    local infrastructure = clamp((source.structureCount or 0) / 6, 0, 1)
    local danger = source.signals.dangerActive and 1 or 0

    local reliefNeed = clamp(
        (1 - foodSecurity) * 0.40
            + (1 - waterSecurity) * 0.40
            + criticalRatio * 0.20,
        0,
        1
    )

    local securityNeed = clamp(
        danger * 0.55
            + (1 - safety) * 0.30
            + criticalRatio * 0.15,
        0,
        1
    )

    local infrastructureNeed = clamp(
        (1 - infrastructure) * 0.70
            + (1 - reserveHealth) * 0.15
            + (1 - health) * 0.15,
        0,
        1
    )

    local prosperityProxy = clamp(
        reserveHealth * 0.30
            + foodSecurity * 0.20
            + waterSecurity * 0.15
            + infrastructure * 0.20
            + health * 0.15,
        0,
        1
    )

    local unrestProxy = clamp(
        (1 - safety) * 0.30
            + (1 - social) * 0.25
            + criticalRatio * 0.25
            + (1 - foodSecurity) * 0.10
            + (1 - waterSecurity) * 0.10,
        0,
        1
    )

    local legitimacy = clamp(
        safety * 0.25
            + social * 0.20
            + health * 0.15
            + foodSecurity * 0.10
            + waterSecurity * 0.10
            + prosperityProxy * 0.20
            - criticalRatio * 0.20
            - danger * 0.15,
        0,
        1
    )

    local suggestedTaxRate = clamp(
        0.08
            + prosperityProxy * 0.04
            - unrestProxy * 0.05
            - reliefNeed * 0.02,
        0.03,
        0.16
    )

    local budget = normalizeBudget(
        0.20 + securityNeed * 0.80,
        0.20 + reliefNeed * 0.80,
        0.20 + infrastructureNeed * 0.60,
        0.35
    )

    local decision = "STEADY"
    if reliefNeed >= 0.70 then
        decision = "EMERGENCY_RELIEF"
    elseif securityNeed >= 0.70 then
        decision = "INCREASE_SECURITY"
    elseif infrastructureNeed >= 0.70 then
        decision = "INVEST_INFRASTRUCTURE"
    elseif unrestProxy >= 0.55 then
        decision = "REDUCE_PRESSURE"
    elseif prosperityProxy >= 0.75 and legitimacy >= 0.70 then
        decision = "CONSOLIDATE_GROWTH"
    end

    return {
        schemaVersion = GovernanceAdvisory.SchemaVersion,
        decision = decision,
        legitimacy = round(legitimacy * 100, 1),
        prosperityProxy = round(prosperityProxy * 100, 1),
        unrestProxy = round(unrestProxy * 100, 1),
        reliefNeed = round(reliefNeed * 100, 1),
        securityNeed = round(securityNeed * 100, 1),
        infrastructureNeed = round(infrastructureNeed * 100, 1),
        suggestedTaxRatePct = round(suggestedTaxRate * 100, 2),
        budgetSecurityPct = round(budget.security * 100, 1),
        budgetReliefPct = round(budget.relief * 100, 1),
        budgetInfrastructurePct = round(budget.infrastructure * 100, 1),
        budgetAdministrationPct = round(budget.administration * 100, 1),
    }
end

return GovernanceAdvisory

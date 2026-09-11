local FiscalPolicy = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function FiscalPolicy.Plan(snapshot, config)
    config = config or {}
    local pop = math.max(1, snapshot.population.total or 1)
    local stocks = snapshot.stocks or {}
    local safety = clamp((snapshot.population.averageSafety or 100) / 100, 0, 1)
    local health = clamp(snapshot.population.averageHealthRatio or 1, 0, 1)
    local criticalRatio = (snapshot.population.critical or 0) / pop
    local foodCoverage = (stocks.Food or 0) / math.max(1, pop * 2.2)
    local waterCoverage = (stocks.Water or 0) / math.max(1, pop * 2.0)
    local infrastructure = clamp((snapshot.structureCount or 0) / math.max(1, config.infrastructureTarget or 6), 0, 1)

    local reliefNeed = clamp((1 - math.min(foodCoverage, 1)) * 0.4 + (1 - math.min(waterCoverage, 1)) * 0.35 + criticalRatio * 0.25, 0, 1)
    local securityNeed = clamp((1 - safety) * 0.7 + ((snapshot.signals or {}).dangerActive and 0.3 or 0), 0, 1)
    local infrastructureNeed = clamp(1 - infrastructure, 0, 1)
    local legitimacy = clamp(health * 0.25 + safety * 0.25 + (1 - criticalRatio) * 0.2 + math.min(foodCoverage, 1) * 0.15 + math.min(waterCoverage, 1) * 0.15, 0, 1)

    local taxRate = clamp((config.baseTaxRate or 0.08) + (legitimacy - 0.5) * 0.04 - reliefNeed * 0.04, 0.02, 0.16)
    local revenueEstimate = pop * (config.taxBasePerCapita or 2) * taxRate
    local reliefWeight = 0.15 + reliefNeed * 0.55
    local securityWeight = 0.15 + securityNeed * 0.45
    local infraWeight = 0.1 + infrastructureNeed * 0.4
    local totalWeight = reliefWeight + securityWeight + infraWeight

    local plan = {
        taxRate = taxRate,
        estimatedRevenue = revenueEstimate,
        legitimacy = legitimacy,
        reliefNeed = reliefNeed,
        securityNeed = securityNeed,
        infrastructureNeed = infrastructureNeed,
        allocations = {
            relief = revenueEstimate * reliefWeight / totalWeight,
            security = revenueEstimate * securityWeight / totalWeight,
            infrastructure = revenueEstimate * infraWeight / totalWeight,
        },
    }

    if reliefNeed >= 0.7 then plan.decision = "EMERGENCY_RELIEF"
    elseif securityNeed >= 0.7 then plan.decision = "SECURITY_PRIORITY"
    elseif infrastructureNeed >= 0.65 then plan.decision = "BUILD_CAPACITY"
    elseif legitimacy < 0.45 then plan.decision = "REDUCE_PRESSURE"
    else plan.decision = "BALANCED_BUDGET" end

    return plan
end

function FiscalPolicy.TransactionPlan(plan, tick)
    local idPrefix = "k11:" .. tostring(tick)
    return {
        { id = idPrefix .. ":revenue", kind = "credit", amount = plan.estimatedRevenue, reason = "tax_revenue_projection" },
        { id = idPrefix .. ":relief", kind = "reserve", amount = plan.allocations.relief, reason = "relief_budget" },
        { id = idPrefix .. ":security", kind = "reserve", amount = plan.allocations.security, reason = "security_budget" },
        { id = idPrefix .. ":infrastructure", kind = "reserve", amount = plan.allocations.infrastructure, reason = "infrastructure_budget" },
    }
end

return FiscalPolicy

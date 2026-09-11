local GovernanceAdvisory = require(script.Parent.GovernanceAdvisory)

local K5Verifier = {}

local VALID_DECISIONS = {
    STEADY = true,
    EMERGENCY_RELIEF = true,
    INCREASE_SECURITY = true,
    INVEST_INFRASTRUCTURE = true,
    REDUCE_PRESSURE = true,
    CONSOLIDATE_GROWTH = true,
}

local function sameMap(before, after)
    for key, value in pairs(before) do
        if after[key] ~= value then return false, key end
    end
    for key, value in pairs(after) do
        if before[key] ~= value then return false, key end
    end
    return true, nil
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function K5Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
    local failures = {}

    if not scope or scope.Name ~= "K5Governance" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
        table.insert(failures, "write_boundary")
    end
    if result.schemaVersion ~= GovernanceAdvisory.SchemaVersion then table.insert(failures, "schema") end
    if not VALID_DECISIONS[result.decision] then table.insert(failures, "decision") end

    for _, key in ipairs({
        "legitimacy", "prosperityProxy", "unrestProxy",
        "reliefNeed", "securityNeed", "infrastructureNeed",
        "budgetSecurityPct", "budgetReliefPct", "budgetInfrastructurePct", "budgetAdministrationPct",
    }) do
        local value = result[key]
        if not finite(value) or value < 0 or value > 100 then table.insert(failures, "metric:" .. key) end
    end

    if not finite(result.suggestedTaxRatePct)
        or result.suggestedTaxRatePct < 3
        or result.suggestedTaxRatePct > 16
    then
        table.insert(failures, "tax_rate")
    end

    local budgetTotal = result.budgetSecurityPct
        + result.budgetReliefPct
        + result.budgetInfrastructurePct
        + result.budgetAdministrationPct
    if math.abs(budgetTotal - 100) > 0.3 then table.insert(failures, "budget_sum") end

    local stocksUnchanged, stockKey = sameMap(stocksBefore, stocksAfter)
    if not stocksUnchanged then table.insert(failures, "stock_write:" .. tostring(stockKey)) end

    local agentsUnchanged, agentKey = sameMap(agentsBefore, agentsAfter)
    if not agentsUnchanged then table.insert(failures, "agent_write:" .. tostring(agentKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K5Status", status)
    scope:SetAttribute("K5Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K5Verifier

local K11Verifier = {}

local function sameStock(a, b)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water" }) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

function K11Verifier.Verify(scope, beforeStocks, afterStocks, plan)
    local failures = {}
    if not sameStock(beforeStocks, afterStocks) then table.insert(failures, "stock_mutation") end
    if plan.taxRate < 0 or plan.taxRate > 0.25 then table.insert(failures, "tax_bounds") end
    if plan.legitimacy < 0 or plan.legitimacy > 1 then table.insert(failures, "legitimacy_bounds") end
    for name, amount in pairs(plan.allocations or {}) do
        if amount < 0 or amount ~= amount then table.insert(failures, "allocation_" .. name) end
    end
    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K11Status", status)
    scope:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K11Verifier

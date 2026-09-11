local K8Verifier = {}

local function sameStock(a, b)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water" }) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

function K8Verifier.Verify(scope, beforeStocks, afterStocks, summary)
    local failures = {}
    if not sameStock(beforeStocks, afterStocks) then table.insert(failures, "stock_mutation") end
    if summary.proposalCount < 0 or summary.viableCount < 0 then table.insert(failures, "negative_count") end
    if summary.viableCount > summary.proposalCount then table.insert(failures, "viable_gt_total") end
    if summary.totalExpectedProfit ~= summary.totalExpectedProfit then table.insert(failures, "nan_profit") end
    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K8Status", status)
    scope:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K8Verifier

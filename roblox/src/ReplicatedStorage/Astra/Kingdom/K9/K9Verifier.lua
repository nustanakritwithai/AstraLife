local K9Verifier = {}

local function sameStock(a, b)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water" }) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

function K9Verifier.Verify(scope, beforeStocks, afterStocks, summary)
    local failures = {}
    if not sameStock(beforeStocks, afterStocks) then table.insert(failures, "stock_mutation") end
    if summary.settlementCount < 1 then table.insert(failures, "no_settlement_projection") end
    if summary.averageProsperity < 0 or summary.averageProsperity > 100 then table.insert(failures, "prosperity_bounds") end
    if summary.averageScarcity < 0 then table.insert(failures, "scarcity_negative") end
    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K9Status", status)
    scope:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K9Verifier

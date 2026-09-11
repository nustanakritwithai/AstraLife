local K10Verifier = {}

local function sameStock(a, b)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water" }) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

function K10Verifier.Verify(scope, beforeStocks, afterStocks, snapshot)
    local failures = {}
    if not sameStock(beforeStocks, afterStocks) then table.insert(failures, "stock_mutation") end
    if snapshot.balance < 0 then table.insert(failures, "negative_balance") end
    if snapshot.reserved < 0 then table.insert(failures, "negative_reserved") end
    if snapshot.available < 0 then table.insert(failures, "negative_available") end
    if snapshot.reserved > snapshot.balance then table.insert(failures, "reserved_gt_balance") end
    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K10Status", status)
    scope:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K10Verifier

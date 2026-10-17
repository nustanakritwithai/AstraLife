local S11Verifier = {}
function S11Verifier.Verify(Catalog, scope)
    local errors = {}
    local quote, reason = Catalog.QuoteCycle("Quarry", { efficiency = 1, outputFreeCapacity = 10, availableFuel = 2 })
    if not quote or reason then table.insert(errors, "quarry_quote") end
    local blocked, blockedReason = Catalog.QuoteCycle("Quarry", { efficiency = 1, outputFreeCapacity = 10, availableFuel = 0 })
    if blocked ~= nil or blockedReason ~= "fuel_low" then table.insert(errors, "fuel_gate") end
    if quote and quote.requiresAuthoritativeResourceCommit ~= true then table.insert(errors, "authority_flag") end
    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("S11Status", status)
    scope:SetAttribute("S11Errors", table.concat(errors, ","))
    return status, errors
end
return S11Verifier

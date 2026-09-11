local S2Verifier = {}

function S2Verifier.Verify(contracts, scope)
    local errors, count = {}, 0
    for sourceKind, contract in pairs(contracts.All()) do
        count += 1
        if type(sourceKind) ~= "string" or sourceKind == "" then table.insert(errors, "invalid_source") end
        if type(contract.toolClass) ~= "string" or contract.toolClass == "" then table.insert(errors, "invalid_tool:" .. tostring(sourceKind)) end
        if type(contract.hardness) ~= "number" or contract.hardness <= 0 then table.insert(errors, "invalid_hardness:" .. tostring(sourceKind)) end
        local yields = 0
        for _, amount in pairs(contract.yields or {}) do
            if type(amount) ~= "number" or amount < 0 then table.insert(errors, "invalid_yield:" .. tostring(sourceKind)) end
            yields += amount
        end
        if yields <= 0 then table.insert(errors, "empty_yield:" .. tostring(sourceKind)) end
    end
    local status = (#errors == 0 and count > 0) and "PASS" or "ERROR"
    scope:SetAttribute("S2Status", status)
    scope:SetAttribute("ContractCount", count)
    scope:SetAttribute("S2Errors", table.concat(errors, ","))
    return status, errors
end

return S2Verifier

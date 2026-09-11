local S12Verifier = {}
function S12Verifier.Verify(Policy, scope)
    local errors = {}
    local wear = Policy.Wear(10, 10, 2, 1)
    if wear.after ~= 8 or wear.loss ~= 2 then table.insert(errors, "wear") end
    local repair = Policy.RepairQuote(50, 100, { MetalFragment = 10 }, 1)
    if repair.restore ~= 50 or repair.materials.MetalFragment ~= 5 then table.insert(errors, "repair") end
    local maintained = Policy.StructureDecayQuote(1000, 2, 1, true, 100)
    local neglected = Policy.StructureDecayQuote(1000, 2, 1, false, 100)
    if maintained.damage >= neglected.damage then table.insert(errors, "upkeep_decay") end
    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("S12Status", status)
    scope:SetAttribute("S12Errors", table.concat(errors, ","))
    return status, errors
end
return S12Verifier

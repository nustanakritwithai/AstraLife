local S9Verifier = {}
function S9Verifier.Verify(catalog, scope)
    local errors, count = {}, 0
    for id, part in pairs(catalog.All()) do
        count += 1
        if type(part.family) ~= "string" or part.family == "" then table.insert(errors, "family:" .. id) end
        if type(part.tier) ~= "number" or part.tier < 1 then table.insert(errors, "tier:" .. id) end
        if type(part.maxHealth) ~= "number" or part.maxHealth <= 0 then table.insert(errors, "health:" .. id) end
        if typeof(part.size) ~= "Vector3" then table.insert(errors, "size:" .. id) end
        if part.upgradeTo and not catalog.Get(part.upgradeTo) then table.insert(errors, "upgrade_target:" .. id) end
    end
    local status = (#errors == 0 and count > 0) and "PASS" or "ERROR"
    scope:SetAttribute("S9Status", status)
    scope:SetAttribute("PartTypeCount", count)
    scope:SetAttribute("S9Errors", table.concat(errors, ","))
    return status, errors
end
return S9Verifier

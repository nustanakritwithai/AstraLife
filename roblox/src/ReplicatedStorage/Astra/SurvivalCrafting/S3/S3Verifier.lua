local S3Verifier = {}

function S3Verifier.Verify(catalog, scope)
    local errors, count = {}, 0
    for id, tool in pairs(catalog.All()) do
        count += 1
        if type(tool.class) ~= "string" then table.insert(errors, "class:" .. id) end
        if type(tool.tier) ~= "number" or tool.tier < 0 then table.insert(errors, "tier:" .. id) end
        if type(tool.efficiency) ~= "number" or tool.efficiency <= 0 then table.insert(errors, "efficiency:" .. id) end
        if type(tool.maxDurability) ~= "number" or tool.maxDurability <= 0 then table.insert(errors, "durability:" .. id) end
    end
    scope:SetAttribute("S3Status", #errors == 0 and "PASS" or "ERROR")
    scope:SetAttribute("ToolCount", count)
    scope:SetAttribute("S3Errors", table.concat(errors, ","))
    return #errors == 0, errors
end
return S3Verifier

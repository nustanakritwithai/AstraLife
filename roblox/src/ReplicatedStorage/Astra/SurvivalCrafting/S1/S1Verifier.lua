local S1Verifier = {}

local VALID_KINDS = {
    raw = true, processed = true, component = true, ore = true, currency = true,
    tool = true, station_kit = true, build_part = true, food = true, food_raw = true,
    drink = true,
}

function S1Verifier.Verify(catalog, scope)
    local errors, count = {}, 0
    for id, item in pairs(catalog.All()) do
        count += 1
        if type(id) ~= "string" or id == "" then table.insert(errors, "invalid_id") end
        if not VALID_KINDS[item.kind] then table.insert(errors, "invalid_kind:" .. tostring(id)) end
        if type(item.maxStack) ~= "number" or item.maxStack < 1 then table.insert(errors, "invalid_stack:" .. tostring(id)) end
        if type(item.mass) ~= "number" or item.mass < 0 then table.insert(errors, "invalid_mass:" .. tostring(id)) end
        if item.kind == "tool" and (type(item.durability) ~= "number" or item.durability <= 0) then
            table.insert(errors, "tool_without_durability:" .. tostring(id))
        end
    end
    local status = (#errors == 0 and count > 0) and "PASS" or "ERROR"
    scope:SetAttribute("S1Status", status)
    scope:SetAttribute("ItemCount", count)
    scope:SetAttribute("S1Errors", table.concat(errors, ","))
    return status, errors
end

return S1Verifier

local S7Verifier = {}
function S7Verifier.Verify(catalog, scope)
    local errors, count = {}, 0
    for id, station in pairs(catalog.All()) do
        count += 1
        for _, key in ipairs({"tier", "inputSlots", "fuelSlots", "outputSlots", "queueSlots", "speedMultiplier"}) do
            if type(station[key]) ~= "number" or station[key] < 0 then table.insert(errors, key .. ":" .. id) end
        end
        if station.speedMultiplier <= 0 then table.insert(errors, "speed:" .. id) end
    end
    local status = (#errors == 0 and count > 0) and "PASS" or "ERROR"
    scope:SetAttribute("S7Status", status)
    scope:SetAttribute("StationTypeCount", count)
    scope:SetAttribute("S7Errors", table.concat(errors, ","))
    return status, errors
end
return S7Verifier

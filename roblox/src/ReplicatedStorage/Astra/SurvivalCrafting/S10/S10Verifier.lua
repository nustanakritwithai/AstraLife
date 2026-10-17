local S10Verifier = {}
function S10Verifier.Verify(Profiles, Container, scope)
    local errors = {}
    local furnace = Container.new(Profiles.Get("Furnace"))
    local bad, badReason = furnace:Add("input", { itemId = "Log", quantity = 1, maxStack = 50, tag = "wood" }, "bad")
    if bad ~= nil or badReason ~= "item_not_accepted" then table.insert(errors, "bay_filter") end
    local ok = furnace:Add("input", { itemId = "IronOre", quantity = 10, maxStack = 50, tag = "ore" }, "add1")
    local dup, reason = furnace:Add("input", { itemId = "IronOre", quantity = 10, maxStack = 50, tag = "ore" }, "add1")
    if not ok or not dup or reason ~= "duplicate" then table.insert(errors, "idempotency") end
    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("S10Status", status)
    scope:SetAttribute("S10Errors", table.concat(errors, ","))
    return status, errors
end
return S10Verifier

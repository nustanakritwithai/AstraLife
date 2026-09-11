local S4Verifier = {}

function S4Verifier.Verify(InventoryV2, scope)
    local errors = {}
    local inv = InventoryV2.new(2)
    local a = inv:Add({ itemId = "Log", quantity = 60, maxStack = 50 }, "tx:add")
    local again = inv:Add({ itemId = "Log", quantity = 60, maxStack = 50 }, "tx:add")
    if a.accepted ~= 60 or again.accepted ~= 60 or inv:Count("Log") ~= 60 then table.insert(errors, "idempotent_add") end
    local b = inv:Add({ itemId = "StoneChunk", quantity = 20, maxStack = 50 }, "tx:stone")
    if b.accepted ~= 0 then table.insert(errors, "slot_capacity") end
    local r = inv:Remove("Log", 12, "tx:remove")
    local r2 = inv:Remove("Log", 12, "tx:remove")
    if r.removed ~= 12 or r2.removed ~= 12 or inv:Count("Log") ~= 48 then table.insert(errors, "idempotent_remove") end
    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("S4Status", status)
    scope:SetAttribute("S4Errors", table.concat(errors, ","))
    scope:SetAttribute("SelfTestSlots", inv:GetUsedSlots())
    return status, errors
end
return S4Verifier

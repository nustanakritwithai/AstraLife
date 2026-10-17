local S8Verifier = {}
function S8Verifier.Verify(Catalog, Registry, scope)
    local errors = {}
    local registry = Registry.new(Catalog)
    local quote = registry:Quote("test", "furnace")
    if not quote or quote.scrapCost <= 0 then table.insert(errors, "quote") end
    local denied, deniedReason = registry:Commit("test", "furnace", "tx0", "")
    if denied ~= nil or deniedReason ~= "payment_receipt_required" then table.insert(errors, "receipt_gate") end
    local committed = registry:Commit("test", "furnace", "tx1", "payment:1")
    local duplicate, reason = registry:Commit("test", "furnace", "tx1", "payment:1")
    if not committed or not duplicate or reason ~= "duplicate" then table.insert(errors, "idempotency") end
    local metalTools, dependencyReason = registry:Quote("fresh", "metal_tools")
    if metalTools ~= nil or not string.find(dependencyReason or "", "missing:") then table.insert(errors, "dependencies") end
    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("S8Status", status)
    scope:SetAttribute("S8Errors", table.concat(errors, ","))
    return status, errors
end
return S8Verifier

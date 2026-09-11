local I2Verifier = {}

local function makeFields(overrides)
    local fields = {
        transactionId = "i2-tx-0001",
        actorId = "player-1",
        worldTick = 1000,
        cellKey = "chunk:0,0",
        worldResourceType = "Wood",
        sourceKind = "Tree",
        actualWithdrawn = 1,
        toolClass = "axe",
        toolTier = 0,
    }
    for key, value in pairs(overrides or {}) do fields[key] = value end
    return fields
end

function I2Verifier.Verify(adapter, scope)
    local errors = {}

    local receipt = adapter.BuildReceipt(makeFields())
    local roundtripOk = receipt ~= nil
        and adapter.ValidateReceipt(receipt) == true
        and receipt.provenance == "LivingWorld"
    if not roundtripOk then table.insert(errors, "roundtrip") end

    local missingFields = makeFields()
    missingFields.transactionId = nil
    local missingReceipt, missingReason = adapter.BuildReceipt(missingFields)
    if missingReceipt ~= nil or missingReason ~= "invalid_receipt:transactionId" then
        table.insert(errors, "missing_transaction_rejected")
    end

    local treeYields = adapter.Convert(adapter.BuildReceipt(makeFields({ actualWithdrawn = 1 })), { worldUnitsPerAction = 1 })
    local treeOk = treeYields ~= nil and treeYields.Log == 3 and treeYields.Stick == 1
    if treeOk then
        local count = 0
        for _ in pairs(treeYields) do count += 1 end
        treeOk = count == 2
    end
    if not treeOk then table.insert(errors, "tree_full_yield") end

    local fullYields = adapter.Convert(adapter.BuildReceipt(makeFields()), { worldUnitsPerAction = 1 })
    local halfYields = adapter.Convert(adapter.BuildReceipt(makeFields({ actualWithdrawn = 0.5 })), { worldUnitsPerAction = 1 })
    local halfOk = fullYields ~= nil and halfYields ~= nil
    if halfOk then
        for itemId, fullAmount in pairs(fullYields) do
            local halfAmount = halfYields[itemId]
            if halfAmount == nil or halfAmount > math.floor(fullAmount * 0.5) or halfAmount > fullAmount then halfOk = false end
        end
    end
    if not halfOk then table.insert(errors, "half_withdrawal") end

    local forageYields = adapter.Convert(adapter.BuildReceipt(makeFields({ worldResourceType = "Food", sourceKind = "ForageBush", toolClass = "hand" })))
    if forageYields == nil or (forageYields.ForageGreens or 0) <= 0 or forageYields.RawMeat ~= nil then
        table.insert(errors, "forage_do_not_map")
    end

    local waterYields = adapter.Convert(
        adapter.BuildReceipt(makeFields({ worldResourceType = "Water", sourceKind = "WaterSource", toolClass = "hand", actualWithdrawn = 0.15 })),
        { worldUnitsPerAction = 0.05 }
    )
    if waterYields == nil or waterYields.FreshWater ~= 3 then table.insert(errors, "water_conversion") end

    local wrongYields, wrongReason = adapter.Convert(adapter.BuildReceipt(makeFields()), { tool = { class = "pickaxe", tier = 5 } })
    if wrongYields ~= nil or wrongReason ~= "wrong_tool_class" then table.insert(errors, "wrong_tool_rejected") end

    local legacyReceipt = adapter.BuildReceipt(makeFields())
    local legacyOk, legacyReason = false, nil
    if legacyReceipt then
        legacyReceipt.provenance = "Legacy"
        legacyOk, legacyReason = adapter.ValidateReceipt(legacyReceipt)
    end
    if legacyOk or legacyReason ~= "wrong_provenance" then table.insert(errors, "provenance_rejected") end

    local resolveOk = adapter.ResolveSourceKind("Wood") == "Tree"
        and adapter.ResolveSourceKind("Wood", { source = "dead_tree" }) == "DeadTree"
        and adapter.ResolveSourceKind("Stone") == "Rock"
        and adapter.ResolveSourceKind("Food", { source = "forage" }) == "ForageBush"
        and adapter.ResolveSourceKind("Water") == "WaterSource"
    if not resolveOk then table.insert(errors, "resolve_source") end

    local unmappedKind, unmappedReason = adapter.ResolveSourceKind("Crystal")
    if unmappedKind ~= nil or unmappedReason ~= "unmapped_resource" then table.insert(errors, "resolve_unmapped") end

    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("I2Status", status)
    scope:SetAttribute("I2Errors", table.concat(errors, ","))
    return status, errors
end

return I2Verifier

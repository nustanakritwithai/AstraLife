local S0Verifier = {}

local function sameStocks(a, b)
    for _, key in ipairs({"Wood", "Stone", "Food", "Water", "Total", "Capacity"}) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

function S0Verifier.Capture(sourceReader)
    return {
        stocks = sourceReader.ReadStocks(),
        cadence = sourceReader.ReadCadence(),
    }
end

function S0Verifier.Verify(root, before, after)
    local errors = {}
    if not root or root.Name ~= "AstraSurvivalCraftingState" then table.insert(errors, "bad_state_root") end
    if root and root:GetAttribute("OwnsWorldClock") ~= false then table.insert(errors, "world_clock_boundary") end
    if root and root:GetAttribute("OwnsWorldResources") ~= false then table.insert(errors, "world_resource_boundary") end
    if root and root:GetAttribute("OwnsAgentMovement") ~= false then table.insert(errors, "movement_boundary") end
    if root and root:GetAttribute("OwnsAgentRoles") ~= false then table.insert(errors, "role_boundary") end
    if before and after and not sameStocks(before.stocks, after.stocks) then table.insert(errors, "stock_write_leak") end

    local status = #errors == 0 and "PASS" or "ERROR"
    if root then
        root:SetAttribute("S0Status", status)
        root:SetAttribute("S0Errors", table.concat(errors, ","))
    end
    return status, errors
end

return S0Verifier

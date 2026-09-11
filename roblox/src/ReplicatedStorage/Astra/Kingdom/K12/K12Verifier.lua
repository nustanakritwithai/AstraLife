local K12Verifier = {}

local function sameStock(a, b)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water" }) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

local function roleMap(agents)
    local out = {}
    if agents then
        for _, agent in ipairs(agents:GetChildren()) do
            if agent:IsA("Model") then out[agent.Name] = agent:GetAttribute("Role") end
        end
    end
    return out
end

local function sameMap(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

function K12Verifier.Capture(sourceReader)
    return { stocks = sourceReader.ReadStocks(), roles = roleMap(sourceReader.Agents()) }
end

function K12Verifier.Verify(scope, before, after, snapshot)
    local failures = {}
    if not sameStock(before.stocks, after.stocks) then table.insert(failures, "stock_mutation") end
    if not sameMap(before.roles, after.roles) then table.insert(failures, "role_mutation") end
    if snapshot.guildCount < 0 or snapshot.warehouseCount < 0 or snapshot.memberCount < 0 then table.insert(failures, "negative_count") end
    if snapshot.averageReputation < 0 or snapshot.averageReputation > 100 then table.insert(failures, "reputation_bounds") end
    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K12Status", status)
    scope:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K12Verifier

local K14Verifier = {}

local function sameStock(a, b)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water" }) do
        if (a[key] or 0) ~= (b[key] or 0) then return false end
    end
    return true
end

local function captureRoles(agents)
    local out = {}
    if agents then
        for _, agent in ipairs(agents:GetChildren()) do
            if agent:IsA("Model") then out[agent.Name] = agent:GetAttribute("Role") end
        end
    end
    return out
end

local function captureSettlementOwners()
    local out = {}
    local folder = workspace:FindFirstChild("AstraSettlements")
    if folder then
        for _, s in ipairs(folder:GetChildren()) do
            if s:IsA("Folder") or s:IsA("Model") then
                out[s.Name] = {
                    owner = s:GetAttribute("OwnerFaction"),
                    faction = s:GetAttribute("FactionId"),
                    lord = s:GetAttribute("LocalLordId"),
                }
            end
        end
    end
    return out
end

local function sameScalarMap(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local function sameOwnerMap(a, b)
    for k, v in pairs(a) do
        local x = b[k]
        if not x or x.owner ~= v.owner or x.faction ~= v.faction or x.lord ~= v.lord then return false end
    end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

function K14Verifier.Capture(sourceReader)
    return {
        stocks = sourceReader.ReadStocks(),
        roles = captureRoles(sourceReader.Agents()),
        owners = captureSettlementOwners(),
    }
end

function K14Verifier.Verify(scope, before, after, snapshot)
    local failures = {}
    if not sameStock(before.stocks, after.stocks) then table.insert(failures, "stock_mutation") end
    if not sameScalarMap(before.roles, after.roles) then table.insert(failures, "role_mutation") end
    if not sameOwnerMap(before.owners, after.owners) then table.insert(failures, "settlement_owner_mutation") end
    if snapshot.factionCount < 0 or snapshot.settlementClaimCount < 0 or snapshot.vassalCount < 0 then table.insert(failures, "negative_count") end
    if snapshot.vassalCount > snapshot.factionCount then table.insert(failures, "vassal_count_invalid") end
    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K14Status", status)
    scope:SetAttribute("VerifierFailures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K14Verifier

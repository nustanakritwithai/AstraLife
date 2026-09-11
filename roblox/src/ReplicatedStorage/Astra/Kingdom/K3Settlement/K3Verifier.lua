local Config = require(script.Parent.Config)

local K3Verifier = {}

local METRICS = {
    "foodSecurity", "waterSecurity", "storageHealth", "infrastructure",
    "averageSafety", "averageSocial", "averageHealth", "danger",
    "prosperity", "stability", "unrest", "resilience",
}

local VALID_STATES = {
    CRISIS = true,
    FRAGILE = true,
    STABLE = true,
    PROSPEROUS = true,
}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sameMap(before, after)
    for key, value in pairs(before) do
        if after[key] ~= value then return false, key end
    end
    for key, value in pairs(after) do
        if before[key] ~= value then return false, key end
    end
    return true, nil
end

function K3Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
    local failures = {}

    if not scope or scope.Name ~= "K3Settlement" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
        table.insert(failures, "write_boundary")
    end
    if result.schemaVersion ~= Config.SchemaVersion then table.insert(failures, "schema") end
    if not VALID_STATES[result.state] then table.insert(failures, "state") end

    for _, key in ipairs(METRICS) do
        local value = result[key]
        if not finite(value) or value < 0 or value > 100 then
            table.insert(failures, "metric:" .. key)
        end
    end

    local stocksUnchanged, stockKey = sameMap(stocksBefore, stocksAfter)
    if not stocksUnchanged then table.insert(failures, "stock_write:" .. tostring(stockKey)) end

    local agentsUnchanged, agentKey = sameMap(agentsBefore, agentsAfter)
    if not agentsUnchanged then table.insert(failures, "agent_write:" .. tostring(agentKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K3Status", status)
    scope:SetAttribute("K3Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K3Verifier

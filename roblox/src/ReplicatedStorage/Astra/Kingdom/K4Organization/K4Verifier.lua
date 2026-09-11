local Config = require(script.Parent.Config)

local K4Verifier = {}

local METRICS = {
    "reserveHealth", "infrastructure", "cohesion",
    "operationalCapacity", "roleCoverage", "reputation",
}

local VALID_STATES = {
    CRITICAL = true,
    STRAINED = true,
    READY = true,
    STRONG = true,
}

local function sameMap(before, after)
    for key, value in pairs(before) do
        if after[key] ~= value then return false, key end
    end
    for key, value in pairs(after) do
        if before[key] ~= value then return false, key end
    end
    return true, nil
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function K4Verifier.Run(scope, result, stocksBefore, stocksAfter, rolesBefore, rolesAfter)
    local failures = {}

    if not scope or scope.Name ~= "K4Organization" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
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

    local rolesUnchanged, roleKey = sameMap(rolesBefore, rolesAfter)
    if not rolesUnchanged then table.insert(failures, "role_write:" .. tostring(roleKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K4Status", status)
    scope:SetAttribute("K4Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K4Verifier

local RecruitmentDemand = require(script.Parent.RecruitmentDemand)

local K6Verifier = {}

local function sameMap(before, after)
    for key, value in pairs(before) do
        if after[key] ~= value then return false, key end
    end
    for key, value in pairs(after) do
        if before[key] ~= value then return false, key end
    end
    return true, nil
end

function K6Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
    local failures = {}

    if not scope or scope.Name ~= "K6Recruitment" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
        table.insert(failures, "write_boundary")
    end
    if result.schemaVersion ~= RecruitmentDemand.SchemaVersion then table.insert(failures, "schema") end
    if result.urgencyPct < 0 or result.urgencyPct > 100 then table.insert(failures, "urgency") end

    for _, role in ipairs(RecruitmentDemand.RoleOrder()) do
        local row = result.needs[role]
        if not row then
            table.insert(failures, "role:" .. role)
        elseif row.current < 0 or row.target < 0 or row.need < 0 then
            table.insert(failures, "role_values:" .. role)
        end
    end

    local stocksUnchanged, stockKey = sameMap(stocksBefore, stocksAfter)
    if not stocksUnchanged then table.insert(failures, "stock_write:" .. tostring(stockKey)) end

    local agentsUnchanged, agentKey = sameMap(agentsBefore, agentsAfter)
    if not agentsUnchanged then table.insert(failures, "agent_or_role_write:" .. tostring(agentKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K6Status", status)
    scope:SetAttribute("K6Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K6Verifier

local MigrationPressure = require(script.Parent.MigrationPressure)

local K7Verifier = {}

local VALID_STATES = {
    CALM = true,
    BUILDING = true,
    PRESSURED = true,
    EXODUS_RISK = true,
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

function K7Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
    local failures = {}

    if not scope or scope.Name ~= "K7Migration" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
        table.insert(failures, "write_boundary")
    end
    if result.schemaVersion ~= MigrationPressure.SchemaVersion then table.insert(failures, "schema") end
    if not VALID_STATES[result.state] then table.insert(failures, "state") end
    if result.averagePressurePct < 0 or result.averagePressurePct > 100 then table.insert(failures, "average_pressure") end
    if result.maxPressurePct < 0 or result.maxPressurePct > 100 then table.insert(failures, "max_pressure") end
    if result.attractionPct < 0 or result.attractionPct > 100 then table.insert(failures, "attraction") end

    local counted = result.counts.STAY + result.counts.CONSIDER + result.counts.REFUGE + result.counts.LEAVE
    if counted ~= result.observedPopulation then table.insert(failures, "population_accounting") end
    if result.candidateCount ~= result.counts.REFUGE + result.counts.LEAVE then
        table.insert(failures, "candidate_accounting")
    end

    local stocksUnchanged, stockKey = sameMap(stocksBefore, stocksAfter)
    if not stocksUnchanged then table.insert(failures, "stock_write:" .. tostring(stockKey)) end

    local agentsUnchanged, agentKey = sameMap(agentsBefore, agentsAfter)
    if not agentsUnchanged then table.insert(failures, "agent_or_position_write:" .. tostring(agentKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K7Status", status)
    scope:SetAttribute("K7Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K7Verifier

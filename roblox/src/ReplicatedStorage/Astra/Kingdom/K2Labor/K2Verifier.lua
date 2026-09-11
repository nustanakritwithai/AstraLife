local Config = require(script.Parent.Config)
local LaborMarket = require(script.Parent.LaborMarket)

local K2Verifier = {}

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

function K2Verifier.Run(scope, result, stocksBefore, stocksAfter, rolesBefore, rolesAfter)
    local failures = {}

    if not scope or scope.Name ~= "K2Labor" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
        table.insert(failures, "write_boundary")
    end
    if result.schemaVersion ~= Config.SchemaVersion then table.insert(failures, "schema") end

    for _, profession in ipairs(LaborMarket.ProfessionOrder()) do
        local row = result.professions[profession]
        if not row then
            table.insert(failures, "profession:" .. profession)
        else
            if not finite(row.pressure) or row.pressure < 0 or row.pressure > 1 then
                table.insert(failures, "pressure:" .. profession)
            end
            if not finite(row.wagePremium)
                or row.wagePremium < Config.MinWagePremium
                or row.wagePremium > Config.MaxWagePremium
            then
                table.insert(failures, "premium:" .. profession)
            end
        end
    end

    local stocksUnchanged, stockKey = sameMap(stocksBefore, stocksAfter)
    if not stocksUnchanged then table.insert(failures, "stock_write:" .. tostring(stockKey)) end

    local rolesUnchanged, roleKey = sameMap(rolesBefore, rolesAfter)
    if not rolesUnchanged then table.insert(failures, "role_write:" .. tostring(roleKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K2Status", status)
    scope:SetAttribute("K2Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K2Verifier

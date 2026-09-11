local Config = require(script.Parent.Config)
local MarketEconomy = require(script.Parent.MarketEconomy)

local K1Verifier = {}

local function sameStocks(before, after)
    for _, key in ipairs({ "Wood", "Stone", "Food", "Water", "Total", "Capacity" }) do
        if before[key] ~= after[key] then return false, key end
    end
    return true, nil
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function K1Verifier.Run(scope, source, result, stocksBefore, stocksAfter)
    local failures = {}

    if not scope or scope.Name ~= "K1Market" or not scope.Parent or scope.Parent.Name ~= "AstraKingdomState" then
        table.insert(failures, "write_boundary")
    end

    if result.schemaVersion ~= Config.SchemaVersion then table.insert(failures, "schema") end
    if not finite(result.averageScarcity) then table.insert(failures, "average_scarcity") end
    if not finite(result.averageVolatility) then table.insert(failures, "average_volatility") end
    if not finite(result.tradeHealth) or result.tradeHealth < 0 or result.tradeHealth > 100 then
        table.insert(failures, "trade_health")
    end
    if not finite(result.stressIndex) or result.stressIndex < 0 or result.stressIndex > 1 then
        table.insert(failures, "stress_index")
    end

    for _, resourceType in ipairs(MarketEconomy.ResourceOrder()) do
        local row = result.resources[resourceType]
        if not row then
            table.insert(failures, "resource:" .. resourceType)
        else
            if not finite(row.price) or row.price <= 0 then table.insert(failures, "price:" .. resourceType) end
            if not finite(row.scarcity) or row.scarcity < Config.MinScarcity or row.scarcity > Config.MaxScarcity then
                table.insert(failures, "scarcity:" .. resourceType)
            end
            if row.stock ~= math.floor((source.stocks[resourceType] or 0) * 100 + 0.5) / 100 then
                table.insert(failures, "stock_projection:" .. resourceType)
            end
        end
    end

    local unchanged, stockKey = sameStocks(stocksBefore, stocksAfter)
    if not unchanged then table.insert(failures, "stock_write:" .. tostring(stockKey)) end

    local status = #failures == 0 and "PASS" or "ERROR"
    scope:SetAttribute("K1Status", status)
    scope:SetAttribute("K1Failures", table.concat(failures, ","))
    return status == "PASS", failures
end

return K1Verifier

local TradeContracts = {}

local GOODS = { "Food", "Water", "Wood", "Stone" }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function priceOf(s, good)
    local prices = s.prices or {}
    return math.max(0.01, prices[good] or 1)
end

local function stockOf(s, good)
    return math.max(0, (s.stocks or {})[good] or 0)
end

local function targetOf(s, good)
    local targets = s.targets or {}
    return math.max(1, targets[good] or math.max(4, (s.population or 1) * 2))
end

function TradeContracts.Evaluate(settlements, routeQuote)
    local proposals = {}
    for i = 1, #settlements do
        local origin = settlements[i]
        for j = 1, #settlements do
            if i ~= j then
                local destination = settlements[j]
                for _, good in ipairs(GOODS) do
                    local surplus = stockOf(origin, good) - targetOf(origin, good) * 1.15
                    local shortage = targetOf(destination, good) - stockOf(destination, good)
                    if surplus > 0 and shortage > 0 then
                        local qty = math.floor(math.min(surplus, shortage) * 100 + 0.5) / 100
                        if qty > 0 then
                            local buy = priceOf(origin, good)
                            local sell = priceOf(destination, good)
                            local route = routeQuote and routeQuote(origin.id, destination.id) or nil
                            local routeCost = route and math.max(0, route.cost or 0) or 0
                            local risk = route and clamp(route.risk or 0, 0, 1) or 0
                            local gross = (sell - buy) * qty
                            local expectedLoss = (sell * qty) * risk * 0.35
                            local net = gross - routeCost - expectedLoss
                            local margin = net / math.max(1, buy * qty + routeCost)
                            table.insert(proposals, {
                                id = string.format("%s>%s:%s", tostring(origin.id), tostring(destination.id), good),
                                originId = origin.id,
                                destinationId = destination.id,
                                good = good,
                                quantity = qty,
                                buyPrice = buy,
                                sellPrice = sell,
                                routeCost = routeCost,
                                risk = risk,
                                expectedProfit = math.floor(net * 100 + 0.5) / 100,
                                margin = math.floor(margin * 10000 + 0.5) / 10000,
                                viable = net > 0 and margin >= 0.05,
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(proposals, function(a, b)
        if a.viable ~= b.viable then return a.viable end
        if a.expectedProfit ~= b.expectedProfit then return a.expectedProfit > b.expectedProfit end
        return a.id < b.id
    end)
    return proposals
end

function TradeContracts.Summary(proposals)
    local viable, profit, top = 0, 0, nil
    for _, p in ipairs(proposals) do
        if p.viable then
            viable += 1
            profit += p.expectedProfit
            if not top then top = p end
        end
    end
    return {
        proposalCount = #proposals,
        viableCount = viable,
        totalExpectedProfit = math.floor(profit * 100 + 0.5) / 100,
        topContractId = top and top.id or "None",
        topGood = top and top.good or "None",
        topExpectedProfit = top and top.expectedProfit or 0,
    }
end

return TradeContracts

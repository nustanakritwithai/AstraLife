local CaravanEconomics = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function CaravanEconomics.BuildPlan(input)
    local quantity = math.max(0, tonumber(input.quantity) or 0)
    local buyPrice = math.max(0, tonumber(input.buyPrice) or 0)
    local sellPrice = math.max(0, tonumber(input.sellPrice) or 0)
    local routeCost = math.max(0, tonumber(input.routeCost) or 0)
    local routeRisk = clamp(tonumber(input.routeRisk) or 0, 0, 1)
    local escortCost = math.max(0, tonumber(input.escortCost) or 0)
    local cargoValue = quantity * buyPrice
    local grossRevenue = quantity * sellPrice
    local expectedLoss = cargoValue * routeRisk
    local totalCost = cargoValue + routeCost + escortCost + expectedLoss
    local expectedProfit = grossRevenue - totalCost
    local margin = totalCost > 0 and expectedProfit / totalCost or 0

    return {
        SourceSettlement = tostring(input.sourceSettlement or "unknown"),
        DestinationSettlement = tostring(input.destinationSettlement or "unknown"),
        Good = tostring(input.good or "Unknown"),
        Quantity = quantity,
        CargoValue = cargoValue,
        GrossRevenue = grossRevenue,
        RouteCost = routeCost,
        RouteRisk = routeRisk * 100,
        EscortCost = escortCost,
        ExpectedLoss = expectedLoss,
        ExpectedProfit = expectedProfit,
        ExpectedMargin = margin * 100,
        Viable = quantity > 0 and expectedProfit > 0,
    }
end

function CaravanEconomics.Aggregate(plans)
    local totalCargo, totalProfit, viable, highRisk = 0, 0, 0, 0
    for _, plan in ipairs(plans) do
        totalCargo += plan.CargoValue or 0
        totalProfit += plan.ExpectedProfit or 0
        if plan.Viable then viable += 1 end
        if (plan.RouteRisk or 0) >= 60 then highRisk += 1 end
    end
    return {
        PlanCount = #plans,
        ViablePlanCount = viable,
        HighRiskPlanCount = highRisk,
        TotalPlannedCargoValue = totalCargo,
        TotalExpectedProfit = totalProfit,
    }
end

return CaravanEconomics

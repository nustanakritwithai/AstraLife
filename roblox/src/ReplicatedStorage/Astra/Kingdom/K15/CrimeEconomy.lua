local CrimeEconomy = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function CrimeEconomy.Evaluate(snapshot, kingdomRoot)
    local stocks = snapshot.stocks
    local population = math.max(1, snapshot.population.total)
    local criticalRatio = snapshot.population.critical / population
    local foodWaterPerCapita = ((stocks.Food or 0) + (stocks.Water or 0)) / population
    local scarcityPressure = clamp(1 - foodWaterPerCapita / 6, 0, 1)
    local dangerPressure = snapshot.signals.dangerActive and 0.65 or 0.1

    local trade = kingdomRoot and kingdomRoot:FindFirstChild("K8TradeContracts")
    local tradeProfit = trade and (trade:GetAttribute("TopExpectedProfit") or 0) or 0
    local tradeAttractiveness = clamp(tradeProfit / 100, 0, 1)

    local organization = kingdomRoot and kingdomRoot:FindFirstChild("K4Organization")
    local capacity = organization and (organization:GetAttribute("OperationalCapacity") or 50) or 50
    local weakSecurity = clamp(1 - capacity / 100, 0, 1)

    local crimePressure = clamp(
        scarcityPressure * 0.34 + criticalRatio * 0.22 + dangerPressure * 0.18
        + tradeAttractiveness * 0.16 + weakSecurity * 0.10,
        0, 1
    )
    local theftRisk = clamp(crimePressure * 0.7 + tradeAttractiveness * 0.3, 0, 1)
    local banditIncentive = clamp(crimePressure * 0.6 + tradeAttractiveness * 0.4, 0, 1)
    local bountyPressure = clamp(crimePressure * 0.75 + dangerPressure * 0.25, 0, 1)

    local state = "LOW"
    if crimePressure >= 0.75 then state = "SEVERE"
    elseif crimePressure >= 0.5 then state = "HIGH"
    elseif crimePressure >= 0.25 then state = "ELEVATED" end

    return {
        CrimePressure = crimePressure * 100,
        TheftRisk = theftRisk * 100,
        BanditIncentive = banditIncentive * 100,
        BountyPressure = bountyPressure * 100,
        SecurityNeed = clamp((crimePressure * 0.8 + weakSecurity * 0.2) * 100, 0, 100),
        ScarcityPressure = scarcityPressure * 100,
        TradeAttractiveness = tradeAttractiveness * 100,
        CrimeState = state,
    }
end

return CrimeEconomy

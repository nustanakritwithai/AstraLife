local MilitaryEconomy = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function MilitaryEconomy.Evaluate(snapshot, kingdomRoot)
    local pop = math.max(1, snapshot.population.total)
    local food = snapshot.stocks.Food or 0
    local water = snapshot.stocks.Water or 0
    local wood = snapshot.stocks.Wood or 0
    local stone = snapshot.stocks.Stone or 0
    local danger = snapshot.signals.dangerActive and 1 or 0

    local crime = kingdomRoot and kingdomRoot:FindFirstChild("K15CrimeEconomy")
    local crimePressure = crime and ((crime:GetAttribute("CrimePressure") or 0) / 100) or 0
    local sovereignty = kingdomRoot and kingdomRoot:FindFirstChild("K14Sovereignty")
    local factionCount = sovereignty and (sovereignty:GetAttribute("FactionCount") or 0) or 0

    local nominalForce = math.max(1, math.floor(pop * 0.25 + 0.5))
    local dailyFoodNeed = nominalForce * 1.5
    local dailyWaterNeed = nominalForce * 2
    local supplyDays = math.min(food / math.max(1, dailyFoodNeed), water / math.max(1, dailyWaterNeed))
    local supplyReadiness = clamp(supplyDays / 7, 0, 1)
    local equipmentReadiness = clamp((wood + stone) / math.max(1, nominalForce * 4), 0, 1)
    local threatPressure = clamp(danger * 0.6 + crimePressure * 0.25 + math.min(factionCount, 3) / 3 * 0.15, 0, 1)
    local mobilizationPressure = clamp(threatPressure * 0.7 + (1 - supplyReadiness) * 0.3, 0, 1)
    local readiness = clamp(supplyReadiness * 0.55 + equipmentReadiness * 0.3 + (1 - crimePressure) * 0.15, 0, 1)
    local upkeep = nominalForce * (1.5 + threatPressure * 0.75)

    local state = "PEACEFUL"
    if mobilizationPressure >= 0.75 then state = "MOBILIZE"
    elseif mobilizationPressure >= 0.5 then state = "ALERT"
    elseif mobilizationPressure >= 0.25 then state = "WATCH" end

    return {
        NominalForceSize = nominalForce,
        SupplyDays = supplyDays,
        SupplyReadiness = supplyReadiness * 100,
        EquipmentReadiness = equipmentReadiness * 100,
        ThreatPressure = threatPressure * 100,
        MobilizationPressure = mobilizationPressure * 100,
        Readiness = readiness * 100,
        ProjectedDailyUpkeep = upkeep,
        ProcurementNeedFood = math.max(0, dailyFoodNeed * 7 - food),
        ProcurementNeedWater = math.max(0, dailyWaterNeed * 7 - water),
        ProcurementNeedMaterials = math.max(0, nominalForce * 4 - (wood + stone)),
        MilitaryState = state,
    }
end

return MilitaryEconomy

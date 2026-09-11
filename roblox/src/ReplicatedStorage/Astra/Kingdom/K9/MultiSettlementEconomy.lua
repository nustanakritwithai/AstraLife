local MultiSettlementEconomy = {}

local GOODS = { "Food", "Water", "Wood", "Stone" }
local BASE = { Food = 4, Water = 3, Wood = 5, Stone = 7 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function MultiSettlementEconomy.Project(settlements)
    local out = {}
    for _, s in ipairs(settlements) do
        local pop = math.max(1, s.population or 1)
        local entry = {
            id = s.id,
            population = pop,
            goods = {},
            prosperity = 0,
            scarcityAverage = 0,
        }
        local scarcityTotal, coverageTotal = 0, 0
        for _, good in ipairs(GOODS) do
            local stock = math.max(0, (s.stocks or {})[good] or 0)
            local demandBase = good == "Food" and 2.2 or good == "Water" and 2.0 or good == "Wood" and 1.2 or 0.9
            local demand = math.max(1, pop * demandBase + ((s.extraDemand or {})[good] or 0))
            local coverage = stock / demand
            local scarcity = clamp(demand / math.max(stock, 1), 0.25, 8)
            local price = BASE[good] * clamp(scarcity ^ 0.72, 0.35, 6)
            entry.goods[good] = {
                stock = stock,
                demand = math.floor(demand * 100 + 0.5) / 100,
                coverage = math.floor(coverage * 1000 + 0.5) / 1000,
                scarcity = math.floor(scarcity * 1000 + 0.5) / 1000,
                price = math.floor(price * 100 + 0.5) / 100,
            }
            scarcityTotal += scarcity
            coverageTotal += clamp(coverage, 0, 1.5)
        end
        entry.scarcityAverage = scarcityTotal / #GOODS
        entry.prosperity = clamp((coverageTotal / #GOODS) * 65 + math.min((s.infrastructure or 0) * 7, 25) + math.min(pop, 20) * 0.5, 0, 100)
        if entry.scarcityAverage >= 3 then entry.state = "CRISIS"
        elseif entry.scarcityAverage >= 1.6 then entry.state = "TIGHT"
        elseif entry.prosperity >= 75 then entry.state = "PROSPEROUS"
        else entry.state = "STABLE" end
        table.insert(out, entry)
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

function MultiSettlementEconomy.WorldSummary(projected)
    local totalPop, crisis, prosperity, scarcity = 0, 0, 0, 0
    for _, s in ipairs(projected) do
        totalPop += s.population
        prosperity += s.prosperity
        scarcity += s.scarcityAverage
        if s.state == "CRISIS" then crisis += 1 end
    end
    local n = math.max(1, #projected)
    return {
        settlementCount = #projected,
        totalPopulation = totalPop,
        crisisCount = crisis,
        averageProsperity = math.floor((prosperity / n) * 10 + 0.5) / 10,
        averageScarcity = math.floor((scarcity / n) * 1000 + 0.5) / 1000,
    }
end

return MultiSettlementEconomy

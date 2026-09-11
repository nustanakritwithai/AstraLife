local RecruitmentDemand = {}

RecruitmentDemand.SchemaVersion = "K6.1"

local ROLE_ORDER = { "Scout", "Gatherer", "Builder" }
local TARGET_RATIOS = {
    Scout = 0.25,
    Gatherer = 0.40,
    Builder = 0.25,
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function countRoles(agentsFolder)
    local counts = { Scout = 0, Gatherer = 0, Builder = 0, Other = 0 }
    if not agentsFolder then return counts end
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local role = agent:GetAttribute("Role")
            if counts[role] ~= nil then counts[role] += 1 else counts.Other += 1 end
        end
    end
    return counts
end

function RecruitmentDemand.Compute(source, agentsFolder)
    local population = source.population.total or 0
    local divisor = math.max(1, population)
    local roleCounts = countRoles(agentsFolder)
    local needs = {}

    local foodPerCapita = (source.stocks.Food or 0) / divisor
    local waterPerCapita = (source.stocks.Water or 0) / divisor
    local materialPerCapita = ((source.stocks.Wood or 0) + (source.stocks.Stone or 0)) / divisor
    local criticalRatio = (source.population.critical or 0) / divisor
    local infrastructureGap = clamp((4 - (source.structureCount or 0)) / 4, 0, 1)

    for _, role in ipairs(ROLE_ORDER) do
        local target = math.max(1, math.ceil(population * TARGET_RATIOS[role]))
        local contextualBonus = 0

        if role == "Gatherer" then
            if foodPerCapita < 3 then contextualBonus += 1 end
            if waterPerCapita < 3 then contextualBonus += 1 end
            if materialPerCapita < 3 then contextualBonus += 1 end
            if criticalRatio >= 0.25 then contextualBonus += 1 end
        elseif role == "Builder" then
            if infrastructureGap >= 0.50 then contextualBonus += 1 end
            if (source.stocks.Wood or 0) >= 3 and (source.stocks.Stone or 0) >= 3 and (source.structureCount or 0) < 6 then
                contextualBonus += 1
            end
        elseif role == "Scout" then
            if source.signals.dangerActive then contextualBonus += 1 end
            if (source.resourceCount or 0) < math.max(4, population) then contextualBonus += 1 end
        end

        local need = math.max(0, target - (roleCounts[role] or 0)) + contextualBonus
        needs[role] = {
            current = roleCounts[role] or 0,
            target = target,
            contextualBonus = contextualBonus,
            need = need,
        }
    end

    local highestRole, highestNeed = ROLE_ORDER[1], -1
    local totalNeed = 0
    for _, role in ipairs(ROLE_ORDER) do
        totalNeed += needs[role].need
        if needs[role].need > highestNeed
            or (needs[role].need == highestNeed and role < highestRole)
        then
            highestRole = role
            highestNeed = needs[role].need
        end
    end

    local urgency = clamp(totalNeed / math.max(1, population + totalNeed), 0, 1)
    return {
        schemaVersion = RecruitmentDemand.SchemaVersion,
        population = population,
        roleCounts = roleCounts,
        needs = needs,
        highestNeedRole = highestRole,
        highestNeedCount = highestNeed,
        totalNeed = totalNeed,
        urgencyPct = math.floor(urgency * 1000 + 0.5) / 10,
        suggestedOffer = highestNeed > 0 and ("RECRUIT_" .. string.upper(highestRole)) or "NONE",
    }
end

function RecruitmentDemand.RoleOrder()
    return table.clone(ROLE_ORDER)
end

return RecruitmentDemand

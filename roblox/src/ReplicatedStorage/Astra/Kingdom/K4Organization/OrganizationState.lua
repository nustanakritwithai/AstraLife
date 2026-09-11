local Config = require(script.Parent.Config)

local OrganizationState = {}

local ROLE_ORDER = { "Scout", "Gatherer", "Builder" }

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function round(value, places)
    local factor = 10 ^ (places or 2)
    return math.floor(value * factor + 0.5) / factor
end

local function countRoles(agentsFolder)
    local counts = { Scout = 0, Gatherer = 0, Builder = 0, Other = 0 }
    if not agentsFolder then return counts end
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local role = agent:GetAttribute("Role")
            if counts[role] ~= nil then
                counts[role] += 1
            else
                counts.Other += 1
            end
        end
    end
    return counts
end

local function classify(cohesion, capacity, reserveHealth)
    if reserveHealth < 0.25 or capacity < 0.35 then return "CRITICAL" end
    if cohesion < 0.50 or capacity < 0.55 then return "STRAINED" end
    if cohesion >= 0.78 and capacity >= 0.75 then return "STRONG" end
    return "READY"
end

function OrganizationState.Compute(source, agentsFolder)
    local members = source.population.total or 0
    local divisor = math.max(1, members)
    local criticalRatio = (source.population.critical or 0) / divisor
    local safety = clamp((source.population.averageSafety or 100) / 100, 0, 1)
    local social = clamp((source.population.averageSocial or 100) / 100, 0, 1)
    local health = clamp(source.population.averageHealthRatio or 1, 0, 1)
    local reservePerMember = (source.stocks.Total or 0) / divisor
    local reserveHealth = clamp(reservePerMember / Config.TargetReservePerMember, 0, 1)
    local infrastructure = clamp((source.structureCount or 0) / Config.TargetStructureCount, 0, 1)
    local roleCounts = countRoles(agentsFolder)

    local cohesion = clamp(
        social * 0.45
            + safety * 0.25
            + (1 - criticalRatio) * 0.30,
        0,
        1
    )

    local operationalCapacity = clamp(
        reserveHealth * 0.30
            + infrastructure * 0.25
            + health * 0.25
            + safety * 0.20,
        0,
        1
    )

    local roleCoverage = 0
    for _, role in ipairs(ROLE_ORDER) do
        if roleCounts[role] > 0 then roleCoverage += 1 end
    end
    roleCoverage /= #ROLE_ORDER

    local reputation = clamp(
        cohesion * 0.35
            + operationalCapacity * 0.40
            + roleCoverage * 0.25,
        0,
        1
    )

    return {
        schemaVersion = Config.SchemaVersion,
        organizationId = "astra-colony",
        memberCount = members,
        roleCounts = roleCounts,
        reservePerMember = round(reservePerMember, 2),
        reserveHealth = round(reserveHealth * 100, 1),
        infrastructure = round(infrastructure * 100, 1),
        cohesion = round(cohesion * 100, 1),
        operationalCapacity = round(operationalCapacity * 100, 1),
        roleCoverage = round(roleCoverage * 100, 1),
        reputation = round(reputation * 100, 1),
        state = classify(cohesion, operationalCapacity, reserveHealth),
    }
end

function OrganizationState.RoleOrder()
    return table.clone(ROLE_ORDER)
end

return OrganizationState

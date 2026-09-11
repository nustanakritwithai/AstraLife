local WorldSimRelationships = {}

local relations = {}
local MAX_RELATIONS = 24
local CONTACT_DISTANCE = 12

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function rootOf(agent)
    return agent:FindFirstChild("HumanoidRootPart")
end

local function ensureOwner(name)
    if not relations[name] then relations[name] = {} end
    return relations[name]
end

local function ensureRelation(aName, bName)
    local owner = ensureOwner(aName)
    if not owner[bName] then
        owner[bName] = {
            score = 0,
            trust = 50,
            gratitude = 0,
            grudge = 0,
            loyalty = 0,
            interactions = 0,
            lastInteractionTick = 0,
        }
    end
    return owner[bName]
end

local function strength(rel)
    return math.abs(rel.score) + rel.grudge + rel.gratitude + rel.loyalty + rel.trust * 0.2
end

local function prune(agentName)
    local owner = relations[agentName]
    if not owner then return end
    local ranked = {}
    for otherName, rel in pairs(owner) do
        table.insert(ranked, { name = otherName, rel = rel, strength = strength(rel) })
    end
    table.sort(ranked, function(a, b)
        if a.strength == b.strength then return a.name < b.name end
        return a.strength > b.strength
    end)
    for i = MAX_RELATIONS + 1, #ranked do
        owner[ranked[i].name] = nil
    end
end

local function interact(a, b, tick, socialBonus)
    local rel = ensureRelation(a.Name, b.Name)
    local delta = 0.35 + socialBonus
    rel.score = clamp(rel.score + delta, -100, 100)
    rel.trust = clamp(rel.trust + 0.15 + socialBonus * 0.25, 0, 100)
    rel.gratitude = clamp(rel.gratitude + socialBonus * 0.3, 0, 100)
    rel.loyalty = clamp(rel.loyalty + socialBonus * 0.15, 0, 100)
    rel.interactions += 1
    rel.lastInteractionTick = tick
end

local function syncSummary(agent)
    local owner = relations[agent.Name] or {}
    local topName, topRel = "None", nil
    local count = 0
    for otherName, rel in pairs(owner) do
        count += 1
        if not topRel or strength(rel) > strength(topRel) or (strength(rel) == strength(topRel) and otherName < topName) then
            topName, topRel = otherName, rel
        end
    end
    agent:SetAttribute("RelationCount", count)
    agent:SetAttribute("RelationTopAgent", topName)
    agent:SetAttribute("RelationTopScore", topRel and math.floor(topRel.score * 10 + 0.5) / 10 or 0)
    agent:SetAttribute("RelationTopTrust", topRel and math.floor(topRel.trust * 10 + 0.5) / 10 or 0)
end

function WorldSimRelationships.Tick(agentsFolder, tick, relationsFolder)
    local agents = {}
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") and rootOf(agent) then table.insert(agents, agent) end
    end
    table.sort(agents, function(a, b) return a.Name < b.Name end)

    local interactions = 0
    for i = 1, #agents do
        for j = i + 1, #agents do
            local a, b = agents[i], agents[j]
            local distance = (rootOf(a).Position - rootOf(b).Position).Magnitude
            if distance <= CONTACT_DISTANCE then
                local socialBonus = 0
                if a:GetAttribute("Goal") == "Socialize" or b:GetAttribute("Goal") == "Socialize" then
                    socialBonus = 0.8
                end
                interact(a, b, tick, socialBonus)
                interact(b, a, tick, socialBonus)
                interactions += 1
            end
        end
    end

    for _, agent in ipairs(agents) do
        local owner = relations[agent.Name]
        if owner then
            for _, rel in pairs(owner) do
                local age = tick - (rel.lastInteractionTick or 0)
                if age > 30 then
                    rel.grudge = clamp(rel.grudge - 0.05, 0, 100)
                    rel.gratitude = clamp(rel.gratitude - 0.03, 0, 100)
                    if rel.score > 0 then rel.score = math.max(0, rel.score - 0.02) end
                    if rel.score < 0 then rel.score = math.min(0, rel.score + 0.02) end
                end
            end
        end
        prune(agent.Name)
        syncSummary(agent)
    end

    if relationsFolder then
        relationsFolder:SetAttribute("PairInteractionsLastTick", interactions)
        local pairCount = 0
        for _, owner in pairs(relations) do
            for _ in pairs(owner) do pairCount += 1 end
        end
        relationsFolder:SetAttribute("DirectedRelationCount", pairCount)
    end

    return interactions
end

function WorldSimRelationships.Get(agentName, otherName)
    return relations[agentName] and relations[agentName][otherName] or nil
end

return WorldSimRelationships

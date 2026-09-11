local Determinism = require(script.Parent.WorldSimDeterminism)

local WorldSimTraits = {}

local TRAITS = {
    "Bravery",
    "Greed",
    "Loyalty",
    "Ambition",
    "RiskTolerance",
    "Discipline",
}

function WorldSimTraits.Ensure(agent, seed)
    local out = {}
    for _, trait in ipairs(TRAITS) do
        local attribute = "Trait_" .. trait
        local value = agent:GetAttribute(attribute)
        if value == nil then
            value = Determinism.Range(seed or 1, agent.Name .. ":" .. trait, 0, 0.1, 0.95)
            value = math.floor(value * 1000 + 0.5) / 1000
            agent:SetAttribute(attribute, value)
        end
        out[trait] = value
    end
    return out
end

function WorldSimTraits.Read(agent)
    local out = {}
    for _, trait in ipairs(TRAITS) do
        out[trait] = agent:GetAttribute("Trait_" .. trait) or 0.5
    end
    return out
end

function WorldSimTraits.List()
    return table.clone(TRAITS)
end

return WorldSimTraits

local Traits = require(script.Parent.WorldSimTraits)

local WorldSimMotives = {}

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

function WorldSimMotives.Update(agent)
    local traits = Traits.Read(agent)
    local hunger = (agent:GetAttribute("Hunger") or 100) / 100
    local thirst = (agent:GetAttribute("Thirst") or 100) / 100
    local energy = (agent:GetAttribute("Energy") or 100) / 100
    local safety = (agent:GetAttribute("Safety") or 100) / 100
    local social = (agent:GetAttribute("Social") or 100) / 100
    local carry = agent:GetAttribute("CarryTotal") or 0
    local capacity = math.max(1, agent:GetAttribute("CarryCapacity") or 1)

    local motives = {
        Survival = clamp01(1 - math.min(hunger, thirst, energy)),
        Safety = clamp01((1 - safety) * 0.8 + (1 - traits.RiskTolerance) * 0.2),
        Belonging = clamp01((1 - social) * 0.7 + traits.Loyalty * 0.3),
        Wealth = clamp01(traits.Greed * 0.65 + (carry / capacity) * 0.35),
        Status = clamp01(traits.Ambition * 0.75 + traits.Discipline * 0.25),
        Exploration = clamp01(traits.Bravery * 0.45 + traits.RiskTolerance * 0.35 + (1 - traits.Loyalty) * 0.2),
    }

    local dominant, score = "Survival", -1
    for name, value in pairs(motives) do
        agent:SetAttribute("Motive_" .. name, math.floor(value * 1000 + 0.5) / 1000)
        if value > score or (value == score and name < dominant) then
            dominant, score = name, value
        end
    end
    agent:SetAttribute("DominantMotive", dominant)
    agent:SetAttribute("DominantMotiveScore", math.floor(score * 1000 + 0.5) / 1000)
    return motives, dominant
end

return WorldSimMotives

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
    local injury = (agent:GetAttribute("InjurySeverity") or 0) / 100
    local carry = agent:GetAttribute("CarryTotal") or 0
    local capacity = math.max(1, agent:GetAttribute("CarryCapacity") or 1)
    local relationCount = agent:GetAttribute("RelationCount") or 0
    local relationGrudge = (agent:GetAttribute("RelationGrudgeTotal") or 0) / 100
    local relationFear = (agent:GetAttribute("RelationFearTotal") or 0) / 100
    local relationLoyalty = (agent:GetAttribute("RelationLoyaltyTotal") or 0) / 100
    local leadership = (agent:GetAttribute("Skill_leadership") or 0) / 10
    local trading = (agent:GetAttribute("Skill_trading") or 0) / 10
    local role = agent:GetAttribute("Role") or "Explorer"

    local survivalNeed = 1 - math.min(hunger, thirst, energy)
    local motives = {
        Survival = clamp01(0.4 + survivalNeed * 0.45 + injury * 0.2),
        Wealth = clamp01(0.25 + traits.Greed * 0.4 + (carry / capacity) * 0.2),
        Safety = clamp01(0.35 + (1 - safety) * 0.4 + relationFear * 0.12 + (1 - traits.Bravery) * 0.12),
        Loyalty = clamp01(0.2 + traits.Loyalty * 0.35 + social * 0.18 + relationLoyalty * 0.12),
        Revenge = clamp01(0.1 + relationGrudge * 0.55 + traits.Ambition * 0.08),
        Ambition = clamp01(0.15 + traits.Ambition * 0.5 + leadership * 0.18),
        Duty = clamp01(0.15 + traits.Discipline * 0.3 + ((role == "Scout" or role == "Builder") and 0.2 or 0.05)),
        Trade = clamp01(0.1 + trading * 0.4 + traits.Greed * 0.15 + ((agent:GetAttribute("LaborBestProfession") == "crafter") and 0.08 or 0)),
        Power = clamp01(0.1 + traits.Ambition * 0.25 + leadership * 0.5),
        FamilyClan = clamp01(0.2 + traits.Loyalty * 0.25 + social * 0.2 + math.min(relationCount, 8) * 0.035),
        Fear = clamp01(0.1 + relationFear * 0.35 + injury * 0.25 + (1 - safety) * 0.3),
        Belonging = clamp01((1 - social) * 0.55 + traits.Loyalty * 0.3 + math.min(relationCount, 6) * 0.025),
        Status = clamp01(traits.Ambition * 0.65 + traits.Discipline * 0.2 + leadership * 0.15),
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

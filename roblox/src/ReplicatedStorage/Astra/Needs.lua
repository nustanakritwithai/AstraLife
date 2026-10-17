local Needs = {}

local function clamp100(value)
    return math.clamp(value or 0, 0, 100)
end

function Needs.Create(config)
    return {
        hunger = config.HungerStart,
        thirst = config.ThirstStart,
        energy = config.EnergyStart,
        safety = config.SafetyStart,
        social = config.SocialStart,
    }
end

function Needs.Tick(needs, humanoid, hasThreat, config)
    needs.hunger = clamp100(needs.hunger - config.HungerDecayPerTick)
    needs.thirst = clamp100(needs.thirst - config.ThirstDecayPerTick)
    needs.energy = clamp100(needs.energy - config.EnergyDecayPerTick)
    needs.social = clamp100(needs.social - config.SocialDecayPerTick)

    if hasThreat then
        needs.safety = clamp100(needs.safety - config.SafetyThreatLoss)
    else
        needs.safety = clamp100(needs.safety + config.SafetyRecoveryPerTick)
    end

    local critical = false
    if needs.hunger <= config.HungerCritical then
        humanoid:TakeDamage(config.CriticalNeedDamage)
        critical = true
    end
    if needs.thirst <= config.ThirstCritical then
        humanoid:TakeDamage(config.CriticalNeedDamage)
        critical = true
    end

    if not critical
        and needs.hunger > config.HungerLow
        and needs.thirst > config.ThirstLow
        and humanoid.Health < humanoid.MaxHealth
    then
        humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + config.HealthyRecovery)
    end

    return critical
end

function Needs.Eat(needs, config)
    needs.hunger = clamp100(needs.hunger + config.FoodRestore)
    return needs.hunger
end

function Needs.Drink(needs, config)
    needs.thirst = clamp100(needs.thirst + config.WaterRestore)
    return needs.thirst
end

function Needs.Rest(needs, config, inShelter)
    local gain = config.EnergyRestGain + (inShelter and config.ShelterRestBonus or 0)
    needs.energy = clamp100(needs.energy + gain)
    return needs.energy
end

function Needs.Socialize(needs, config)
    needs.social = clamp100(needs.social + config.SocialRestore)
    return needs.social
end

function Needs.SyncAgent(agent, needs, config)
    agent:SetAttribute("Hunger", math.floor(needs.hunger))
    agent:SetAttribute("Thirst", math.floor(needs.thirst))
    agent:SetAttribute("Energy", math.floor(needs.energy))
    agent:SetAttribute("Safety", math.floor(needs.safety))
    agent:SetAttribute("Social", math.floor(needs.social))
    agent:SetAttribute("NeedFood", needs.hunger <= config.HungerLow)
    agent:SetAttribute("NeedWater", needs.thirst <= config.ThirstLow)
    agent:SetAttribute("NeedRest", needs.energy <= config.EnergyLow)
    agent:SetAttribute("NeedSocial", needs.social <= config.SocialLow)
    agent:SetAttribute("SurvivalCritical", needs.hunger <= config.HungerCritical or needs.thirst <= config.ThirstCritical)
end

function Needs.ColonyDemand(agentsFolder)
    local food = false
    local water = false
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            food = food or agent:GetAttribute("NeedFood") == true
            water = water or agent:GetAttribute("NeedWater") == true
        end
    end
    return food, water
end

return Needs

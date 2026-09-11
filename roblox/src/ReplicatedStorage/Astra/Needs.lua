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

local function environmentMultipliers(humanoid, config)
    local agent = humanoid and humanoid.Parent
    local weather = agent and agent:GetAttribute("ObservedWeather") or "Clear"
    local isNight = agent and agent:GetAttribute("ObservedIsNight") == true or false

    local hunger = 1
    local thirst = 1
    local energy = 1
    local safetyLoss = 0

    if weather == "Rain" then
        thirst *= config.RainThirstDecayMultiplier
    elseif weather == "Storm" then
        energy *= config.StormEnergyDecayMultiplier
        safetyLoss += config.StormSafetyLossPerTick
    end

    if isNight then
        energy *= config.NightEnergyDecayMultiplier
    end

    if agent and (weather ~= "Clear" or isNight) then
        agent:SetAttribute("P5WeatherAffectedNeeds", true)
    end

    return hunger, thirst, energy, safetyLoss
end

function Needs.Tick(needs, humanoid, hasThreat, config)
    local hungerMult, thirstMult, energyMult, environmentSafetyLoss = environmentMultipliers(humanoid, config)
    local agent = humanoid and humanoid.Parent
    local learnedDecay = agent and agent:GetAttribute("P7_SurvivalDecayMultiplier") or 1
    learnedDecay = math.clamp(learnedDecay, config.P7MinSurvivalDecayMultiplier or 0.70, 1)

    needs.hunger = clamp100(needs.hunger - config.HungerDecayPerTick * hungerMult * learnedDecay)
    needs.thirst = clamp100(needs.thirst - config.ThirstDecayPerTick * thirstMult * learnedDecay)
    needs.energy = clamp100(needs.energy - config.EnergyDecayPerTick * energyMult * learnedDecay)
    needs.social = clamp100(needs.social - config.SocialDecayPerTick * learnedDecay)

    if agent and learnedDecay < 0.999 then
        agent:SetAttribute("P7_SurvivalEffectObserved", true)
        local worldState = workspace:FindFirstChild("AstraWorldState")
        if worldState then
            worldState:SetAttribute("P7_SurvivalEffectObserved", true)
        end
    end

    if hasThreat then
        needs.safety = clamp100(needs.safety - config.SafetyThreatLoss - environmentSafetyLoss)
    elseif environmentSafetyLoss > 0 then
        needs.safety = clamp100(needs.safety - environmentSafetyLoss)
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

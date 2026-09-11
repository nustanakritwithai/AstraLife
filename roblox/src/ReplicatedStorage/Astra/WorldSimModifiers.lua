local WorldSimModifiers = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimModifiers.Update(agent, worldState)
    local hunger = agent:GetAttribute("Hunger") or 100
    local thirst = agent:GetAttribute("Thirst") or 100
    local energy = agent:GetAttribute("Energy") or 100
    local safety = agent:GetAttribute("Safety") or 100
    local injury = agent:GetAttribute("InjurySeverity") or 0
    local weather = worldState:GetAttribute("Weather") or "Clear"
    local isNight = worldState:GetAttribute("IsNight") == true

    local survivalFloor = math.min(hunger, thirst) / 100
    local energyFactor = clamp(energy / 100, 0.35, 1)
    local injuryFactor = clamp(1 - injury / 125, 0.35, 1)
    local safetyFactor = clamp(0.65 + safety / 285, 0.65, 1)

    local move = energyFactor * injuryFactor
    local work = clamp((0.55 + survivalFloor * 0.45) * energyFactor * injuryFactor, 0.2, 1)
    local perception = clamp(safetyFactor * (isNight and 0.86 or 1), 0.45, 1)
    local combat = clamp((0.6 + survivalFloor * 0.4) * energyFactor * injuryFactor, 0.25, 1)
    local reasoning = clamp(0.7 + energyFactor * 0.2 + safetyFactor * 0.1, 0.5, 1)

    if weather == "Storm" then
        move *= 0.82
        perception *= 0.78
        work *= 0.86
    elseif weather == "Rain" then
        move *= 0.93
        perception *= 0.92
    end

    local values = {
        Move = clamp(move, 0.2, 1),
        Work = clamp(work, 0.2, 1),
        Perception = clamp(perception, 0.2, 1),
        Combat = clamp(combat, 0.2, 1),
        Reasoning = clamp(reasoning, 0.2, 1),
    }

    for name, value in pairs(values) do
        agent:SetAttribute("WorldMod_" .. name, math.floor(value * 1000 + 0.5) / 1000)
    end

    return values
end

return WorldSimModifiers

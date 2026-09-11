local WorldSimPsychology = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimPsychology.Update(agent, threatsFolder, settlementFolder)
    local bravery = agent:GetAttribute("Trait_Bravery") or 0.5
    local discipline = agent:GetAttribute("Trait_Discipline") or 0.5
    local loyalty = agent:GetAttribute("Trait_Loyalty") or 0.5
    local safety = (agent:GetAttribute("Safety") or 100) / 100
    local social = (agent:GetAttribute("Social") or 100) / 100
    local energy = (agent:GetAttribute("Energy") or 100) / 100
    local injury = (agent:GetAttribute("InjurySeverity") or 0) / 100
    local critical = agent:GetAttribute("SurvivalCritical") == true and 1 or 0
    local threatPressure = threatsFolder and (threatsFolder:GetAttribute("ThreatPressure") or 0) or 0
    local settlementUnrest = settlementFolder and ((settlementFolder:GetAttribute("Unrest") or 0) / 100) or 0

    local fear = clamp(
        threatPressure * 0.35
            + (1 - safety) * 0.25
            + injury * 0.2
            + critical * 0.2
            + settlementUnrest * 0.1
            - bravery * 0.18
            - discipline * 0.08,
        0,
        1
    )
    local stress = clamp(
        fear * 0.45
            + (1 - energy) * 0.2
            + injury * 0.15
            + critical * 0.2
            + (1 - social) * 0.1,
        0,
        1
    )
    local morale = clamp(
        0.55
            + safety * 0.15
            + social * 0.12
            + energy * 0.08
            + loyalty * 0.08
            + discipline * 0.07
            - fear * 0.25
            - injury * 0.12
            - settlementUnrest * 0.08,
        0,
        1
    )

    agent:SetAttribute("PsychologicalFear", math.floor(fear * 1000 + 0.5) / 10)
    agent:SetAttribute("PsychologicalStress", math.floor(stress * 1000 + 0.5) / 10)
    agent:SetAttribute("Morale", math.floor(morale * 1000 + 0.5) / 10)
    agent:SetAttribute("PsychologyState", fear >= 0.7 and "Fearful" or stress >= 0.65 and "Stressed" or morale >= 0.75 and "Confident" or "Stable")

    return { fear = fear, stress = stress, morale = morale }
end

return WorldSimPsychology

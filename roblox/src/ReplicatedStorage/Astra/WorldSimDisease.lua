local Determinism = require(script.Parent.WorldSimDeterminism)

local WorldSimDisease = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimDisease.Update(agentsFolder, climateFolder, hydrologyFolder, settlementFolder, diseaseFolder, tick, seed)
    local climateMult = climateFolder:GetAttribute("DiseaseClimateMultiplier") or 1
    local waterAccess = (hydrologyFolder:GetAttribute("AverageWaterAccess") or 50) / 100
    local population = settlementFolder:GetAttribute("Population") or 0
    local stability = (settlementFolder:GetAttribute("Stability") or 50) / 100
    local unrest = (settlementFolder:GetAttribute("Unrest") or 0) / 100
    local crowding = clamp(population / 8, 0, 2)

    local outbreakPressure = clamp(
        0.08
            + (climateMult - 0.7) * 0.28
            + (1 - waterAccess) * 0.25
            + math.max(0, crowding - 0.8) * 0.18
            + unrest * 0.12
            + (1 - stability) * 0.1,
        0,
        1
    )

    local exposed, sick = 0, 0
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local health = agent:FindFirstChildOfClass("Humanoid")
            local water = (agent:GetAttribute("WaterAccess") or 50) / 100
            local energy = (agent:GetAttribute("Energy") or 100) / 100
            local safety = (agent:GetAttribute("Safety") or 100) / 100
            local susceptibility = clamp((1 - water) * 0.35 + (1 - energy) * 0.25 + (1 - safety) * 0.15 + outbreakPressure * 0.4, 0, 1)
            local roll = Determinism.Random01(seed or 1, agent.Name .. ":disease", tick or 0)
            local burden = agent:GetAttribute("DiseaseBurden") or 0

            if roll < susceptibility * 0.05 then
                burden = clamp(burden + 8 + susceptibility * 12, 0, 100)
            else
                burden = clamp(burden - 1.5, 0, 100)
            end

            if susceptibility >= 0.45 then exposed += 1 end
            if burden >= 25 then sick += 1 end
            agent:SetAttribute("DiseaseExposure", math.floor(susceptibility * 1000 + 0.5) / 10)
            agent:SetAttribute("DiseaseBurden", math.floor(burden * 10 + 0.5) / 10)
            agent:SetAttribute("DiseaseState", burden >= 60 and "Severe" or burden >= 25 and "Sick" or burden > 0 and "Recovering" or "Healthy")
            if health then
                agent:SetAttribute("DiseaseHealthRatio", health.MaxHealth > 0 and math.floor((health.Health / health.MaxHealth) * 1000 + 0.5) / 10 or 0)
            end
        end
    end

    diseaseFolder:SetAttribute("OutbreakPressure", math.floor(outbreakPressure * 1000 + 0.5) / 10)
    diseaseFolder:SetAttribute("ExposedAgents", exposed)
    diseaseFolder:SetAttribute("SickAgents", sick)
    diseaseFolder:SetAttribute("ActiveOutbreak", sick > 0 or outbreakPressure >= 0.7)
    return { pressure = outbreakPressure, exposed = exposed, sick = sick }
end

return WorldSimDisease

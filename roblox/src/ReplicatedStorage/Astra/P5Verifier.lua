local P5Verifier = {}

local REQUIRED_FLAGS = {
    "P5_DayNightChanged",
    "P5_WeatherChanged",
    "P5_WorldEventTriggered",
    "P5_ResourceRegenerated",
    "P5_ThreatSpawned",
    "P5_WeatherAffectedNeeds",
    "P5_EnvironmentResponse",
}

local function liftAgentFlag(worldState, sourceAttribute, targetAttribute)
    local agents = workspace:FindFirstChild("AstraAgents")
    if not agents then
        return false
    end

    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") and agent:GetAttribute(sourceAttribute) == true then
            worldState:SetAttribute(targetAttribute, true)
            return true
        end
    end

    return false
end

function P5Verifier.Update(worldState)
    liftAgentFlag(worldState, "P5WeatherAffectedNeeds", "P5_WeatherAffectedNeeds")
    liftAgentFlag(worldState, "P5EnvironmentResponse", "P5_EnvironmentResponse")

    local passed = true
    for _, key in ipairs(REQUIRED_FLAGS) do
        if worldState:GetAttribute(key) ~= true then
            passed = false
            break
        end
    end

    worldState:SetAttribute("P5Status", passed and "PASS" or "RUNNING")
    return passed
end

return P5Verifier

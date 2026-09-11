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

function P5Verifier.Update(worldState)
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

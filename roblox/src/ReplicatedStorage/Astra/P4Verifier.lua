local P4Verifier = {}

local REQUIRED_FLAGS = {
    "P4_NeedsDecayed",
    "P4_SurvivalGoalObserved",
    "P4_EatObserved",
    "P4_DrinkObserved",
    "P4_RestObserved",
    "P4_SocialObserved",
}

local NEED_ATTRIBUTES = {"Hunger", "Thirst", "Energy", "Safety", "Social"}

local function agentsHaveNeeds()
    local folder = workspace:FindFirstChild("AstraAgents")
    if not folder then return false end
    local count = 0
    for _, agent in ipairs(folder:GetChildren()) do
        if agent:IsA("Model") and agent:GetAttribute("IsAstraAgent") == true then
            count += 1
            for _, attribute in ipairs(NEED_ATTRIBUTES) do
                if agent:GetAttribute(attribute) == nil then
                    return false
                end
            end
        end
    end
    return count >= 3
end

function P4Verifier.Update(worldState)
    local passed = agentsHaveNeeds()
    worldState:SetAttribute("P4_NeedsReady", passed)

    if passed then
        for _, key in ipairs(REQUIRED_FLAGS) do
            if worldState:GetAttribute(key) ~= true then
                passed = false
                break
            end
        end
    end

    worldState:SetAttribute("P4Status", passed and "PASS" or "RUNNING")
    return passed
end

return P4Verifier

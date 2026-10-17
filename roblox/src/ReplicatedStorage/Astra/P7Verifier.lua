local P7Verifier = {}

local function inspectAgents()
    local agents = workspace:FindFirstChild("AstraAgents")
    if not agents then
        return false, false, false, false
    end

    local ready = false
    local xpRecorded = false
    local skillAdvanced = false
    local effectsReady = false

    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then
            ready = ready or agent:GetAttribute("P7LearningReady") == true
            xpRecorded = xpRecorded or (agent:GetAttribute("P7_XP_Total") or 0) > 0
            effectsReady = effectsReady or agent:GetAttribute("P7_EffectsReady") == true

            for _, skill in ipairs({"Scout", "Gatherer", "Builder", "Survival"}) do
                local base = agent:GetAttribute("P7_BaseSkill_" .. skill)
                local current = agent:GetAttribute("Skill_" .. skill)
                if base ~= nil and current ~= nil and current > base + 0.001 then
                    skillAdvanced = true
                end
            end
        end
    end

    return ready, xpRecorded, skillAdvanced, effectsReady
end

function P7Verifier.Update(worldState)
    local ready, xpRecorded, skillAdvanced, effectsReady = inspectAgents()

    worldState:SetAttribute("P7_AgentLearningReady", ready)
    worldState:SetAttribute("P7_ActualXPObserved", xpRecorded)
    worldState:SetAttribute("P7_ActualSkillAdvanced", skillAdvanced)
    worldState:SetAttribute("P7_ActualEffectsReady", effectsReady)

    local passed = worldState:GetAttribute("P7_LearningInitialized") == true
        and worldState:GetAttribute("P7_OutcomeLearningObserved") == true
        and worldState:GetAttribute("P7_XPRecorded") == true
        and worldState:GetAttribute("P7_SkillRecomputed") == true
        and worldState:GetAttribute("P7_EffectApplied") == true
        and worldState:GetAttribute("P7_AntiGrindReady") == true
        and ready
        and xpRecorded
        and skillAdvanced
        and effectsReady

    worldState:SetAttribute("P7Status", passed and "PASS" or "RUNNING")
    return passed
end

return P7Verifier

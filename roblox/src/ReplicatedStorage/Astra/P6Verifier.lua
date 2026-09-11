local P6Verifier = {}

local REQUIRED = {
    "P6_RoleSystemInitialized",
    "P6_InitialAssignment",
    "P6_RoleEvaluated",
    "P6_SkillUpdated",
    "P6_CoverageBalanced",
    "P6_RoleDecisionRecorded",
    "P6_ReassignmentReady",
}

function P6Verifier.Update(worldState)
    local passed = true
    for _, key in ipairs(REQUIRED) do
        if worldState:GetAttribute(key) ~= true then
            passed = false
            break
        end
    end
    worldState:SetAttribute("P6Status", passed and "PASS" or "RUNNING")
    return passed
end

return P6Verifier

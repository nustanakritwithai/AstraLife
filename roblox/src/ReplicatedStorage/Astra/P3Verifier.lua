local P3Verifier = {}

local REQUIRED_FLAGS = {
    "P3_SiteCreated",
    "P3_MaterialsRequested",
    "P3_MaterialDelivered",
    "P3_PhysicalDelivery",
    "P3_AllMaterialsDelivered",
    "P3_BuilderWaited",
    "P3_BuildProgress",
    "P3_BuildCompleted",
}

function P3Verifier.Update(worldState)
    local passed = true
    for _, key in ipairs(REQUIRED_FLAGS) do
        if worldState:GetAttribute(key) ~= true then
            passed = false
            break
        end
    end
    worldState:SetAttribute("P3Status", passed and "PASS" or "RUNNING")
    return passed
end

return P3Verifier

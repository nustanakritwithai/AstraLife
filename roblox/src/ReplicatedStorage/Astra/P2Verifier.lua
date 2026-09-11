local P2Verifier = {}

local P1_KEYS = {
    "P1_ScoutObserved",
    "P1_ScoutSent",
    "P1_GathererReceived",
    "P1_Belief75",
    "P1_RemoteGoal",
    "P1_Verified100",
    "P1_Collected",
    "P1_RoleGuards",
}

local function allTrue(folder, keys)
    for _, key in ipairs(keys) do
        if folder:GetAttribute(key) ~= true then
            return false
        end
    end
    return true
end

function P2Verifier.Update(worldState)
    local typedReady = worldState:GetAttribute("Stock_Wood") ~= nil
        and worldState:GetAttribute("Stock_Stone") ~= nil
        and worldState:GetAttribute("Stock_Food") ~= nil
        and worldState:GetAttribute("Stock_Water") ~= nil

    worldState:SetAttribute("P2_StockTypesReady", typedReady)

    local storage = workspace:FindFirstChild("AstraStructures")
        and workspace.AstraStructures:FindFirstChild("ColonyStorage")
    worldState:SetAttribute("P2_StorageReady", storage ~= nil)

    if allTrue(worldState, P1_KEYS) then
        worldState:SetAttribute("P1Status", "PASS")
    else
        worldState:SetAttribute("P1Status", "RUNNING")
    end

    local p2Pass = typedReady
        and storage ~= nil
        and worldState:GetAttribute("P2_CarryObserved") == true
        and worldState:GetAttribute("P2_DepositObserved") == true
        and worldState:GetAttribute("P2_BuilderSpentRecipe") == true

    if p2Pass then
        worldState:SetAttribute("P2Status", "PASS")
    else
        worldState:SetAttribute("P2Status", "RUNNING")
    end
end

return P2Verifier

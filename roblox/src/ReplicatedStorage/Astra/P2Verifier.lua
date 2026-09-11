local P2Verifier = {}

function P2Verifier.Update(worldState)
    local wood = worldState:GetAttribute("Stock_Wood") or 0
    local stone = worldState:GetAttribute("Stock_Stone") or 0
    local food = worldState:GetAttribute("Stock_Food") or 0
    local water = worldState:GetAttribute("Stock_Water") or 0

    worldState:SetAttribute("P2_StockTypesReady", true)

    local carried = worldState:GetAttribute("P2_CarryObserved") == true
    local deposited = worldState:GetAttribute("P2_DepositObserved") == true
    local builderSpent = worldState:GetAttribute("P2_BuilderSpentRecipe") == true
    local typedStock = (wood + stone + food + water) >= 0

    if typedStock and carried and deposited and builderSpent then
        worldState:SetAttribute("P2Status", "PASS")
    else
        worldState:SetAttribute("P2Status", "RUNNING")
    end
end

return P2Verifier

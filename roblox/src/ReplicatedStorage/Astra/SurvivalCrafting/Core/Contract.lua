local Contract = {}

Contract.Version = "S0-1"
Contract.StateRootName = "AstraSurvivalCraftingState"
Contract.AgentStateName = "AstraWorldState"
Contract.LivingWorldStateName = "AstraLivingWorldState"

Contract.Ownership = {
    OwnsWorldClock = false,
    OwnsWorldGrid = false,
    OwnsWorldResources = false,
    OwnsWorldTransactions = false,
    OwnsAgentMovement = false,
    OwnsAgentGoals = false,
    OwnsAgentRoles = false,
    OwnsAgentSkills = false,
    OwnsLegacyInventory = false,
    OwnsLegacyConstruction = false,
    OwnsCombat = false,
}

function Contract.ApplyOwnershipAttributes(instance)
    instance:SetAttribute("SurvivalCraftingVersion", Contract.Version)
    instance:SetAttribute("IntegrationMode", "isolated-plugin")
    instance:SetAttribute("ReadBoundary", "P7/W7 read-only unless an explicit adapter is installed")
    instance:SetAttribute("WriteBoundary", "Workspace/AstraSurvivalCraftingState only")
    for key, value in pairs(Contract.Ownership) do
        instance:SetAttribute(key, value)
    end
end

return Contract

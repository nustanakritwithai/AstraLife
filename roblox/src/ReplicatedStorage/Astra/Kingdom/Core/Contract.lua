local Contract = {}

Contract.SchemaVersion = "K0.1"
Contract.StateRootName = "AstraKingdomState"
Contract.AgentStateName = "AstraWorldState"
Contract.LivingWorldStateName = "AstraLivingWorldState"

Contract.Ownership = {
    WorldClock = false,
    LivingWorldClock = false,
    WorldGrid = false,
    Terrain = false,
    Biomes = false,
    Climate = false,
    Hydrology = false,
    Ecology = false,
    Snapshot = false,
    Replay = false,
    AgentSkills = false,
    AgentLearning = false,
    AgentGoal = false,
    AgentRole = false,
    AgentMemory = false,
    AgentBelief = false,
    AgentPerception = false,
    ResourceStock = false,
}

Contract.AllowedWriteRoots = {
    Workspace = Contract.StateRootName,
}

function Contract.ApplyOwnershipAttributes(instance)
    instance:SetAttribute("KingdomSchemaVersion", Contract.SchemaVersion)
    for key, value in pairs(Contract.Ownership) do
        instance:SetAttribute("Owns" .. key, value)
    end
end

function Contract.IsReadOnlyDomain(domain)
    return Contract.Ownership[domain] == false
end

return Contract

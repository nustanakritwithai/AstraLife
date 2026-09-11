local Planner = {}

local function hasResourceKnowledge(state, observations, resourceType)
    for _, observation in ipairs(observations.resources) do
        if not resourceType or observation.subtype == resourceType then
            return true
        end
    end
    if state.resourceReport and (not resourceType or state.resourceReport.resourceType == resourceType) then
        return true
    end
    return false
end

local function colonyHasNeed(agentsFolder, attribute)
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") and agent:GetAttribute(attribute) == true then
            return true
        end
    end
    return false
end

local function environmentGoal(state, observations, config)
    local environment = observations.environment or {}
    local weather = environment.weather or "Clear"
    local isNight = environment.isNight == true

    if weather == "Storm" and config.EnvironmentShelterInStorm then
        state.agent:SetAttribute("P5EnvironmentResponse", true)
        state.folders.state:SetAttribute("P5_EnvironmentResponse", true)
        return "Rest", 116
    end

    if isNight and config.EnvironmentShelterAtNight and state.needs.energy < 85 then
        state.agent:SetAttribute("P5EnvironmentResponse", true)
        state.folders.state:SetAttribute("P5_EnvironmentResponse", true)
        return "Rest", 91
    end

    return nil, 0
end

function Planner.ChooseGoal(state, observations, construction, resourceEconomy, config)
    state.preferredResourceType = nil
    local w6BridgeEnabled = state.agent:GetAttribute("W6BridgeEnabled") == true

    -- Immediate danger and critical survival always outrank the environment.
    if #observations.threats > 0 then
        return "Flee", 130
    end

    if state.needs.thirst <= config.ThirstLow then
        if state.inventory:Get("Water") > 0 or resourceEconomy.Get(state.folders.state, "Water") > 0 or w6BridgeEnabled then
            return "Drink", state.needs.thirst <= config.ThirstCritical and 125 or 112
        end
        if state.role == config.Roles.Gatherer then
            state.preferredResourceType = "Water"
            return "GatherResource", state.needs.thirst <= config.ThirstCritical and 122 or 108
        end
        return "WaitForWater", 108
    end

    if state.needs.hunger <= config.HungerLow then
        if state.inventory:Get("Food") > 0 or resourceEconomy.Get(state.folders.state, "Food") > 0 or w6BridgeEnabled then
            return "Eat", state.needs.hunger <= config.HungerCritical and 120 or 106
        end
        if state.role == config.Roles.Gatherer then
            state.preferredResourceType = "Food"
            return "GatherResource", state.needs.hunger <= config.HungerCritical and 118 or 104
        end
        return "WaitForFood", 104
    end

    if state.needs.energy <= config.EnergyLow then
        return "Rest", 100
    end

    local environmentGoalName, environmentScore = environmentGoal(state, observations, config)
    if environmentGoalName then
        return environmentGoalName, environmentScore
    end

    if state.needs.social <= config.SocialLow then
        return "Socialize", 78
    end

    if state.role == config.Roles.Gatherer then
        local requestedType = resourceEconomy.GetMostNeededBuildType(state.folders.state)
        if requestedType then
            state.preferredResourceType = requestedType
            if state.inventory:Get(requestedType) > 0 then
                return "DeliverMaterials", 98
            end
        end

        if colonyHasNeed(state.folders.agents, "NeedWater")
            and resourceEconomy.Get(state.folders.state, "Water") < config.SurvivalStockTargetWater
        then
            state.preferredResourceType = "Water"
        elseif colonyHasNeed(state.folders.agents, "NeedFood")
            and resourceEconomy.Get(state.folders.state, "Food") < config.SurvivalStockTargetFood
        then
            state.preferredResourceType = "Food"
        end

        if state.inventory:GetTotal() > 0 and state.inventory:IsFull() then
            return "DepositResources", 95
        end

        if state.preferredResourceType and state.inventory:Get(state.preferredResourceType) > 0 then
            if resourceEconomy.IsRequestedForBuild(state.folders.state, state.preferredResourceType) then
                return "DeliverMaterials", 94
            end
            return "DepositResources", 92
        end

        if hasResourceKnowledge(state, observations, state.preferredResourceType) and not state.inventory:IsFull() then
            return "GatherResource", 90
        end

        if state.inventory:GetTotal() > 0 then
            return "DepositResources", 84
        end

        if hasResourceKnowledge(state, observations, nil) then
            return "GatherResource", 82
        end

        return "Explore", 40
    end

    if state.role == config.Roles.Builder then
        local active = construction.GetActive()
        if active then
            return "BuildStructure", 95
        end

        if construction.GetNextBlueprint(state.folders, config) then
            return "BuildStructure", 88
        end
        return "Communicate", 45
    end

    if state.role == config.Roles.Scout then
        if #observations.resources > 0 then
            return "Communicate", 85
        end
        return "Explore", 80
    end

    return "Explore", 50
end

return Planner

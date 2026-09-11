local Planner = {}

local function hasResourceKnowledge(state, observations)
    if #observations.resources > 0 then
        return true
    end
    if state.resourceReport then
        return true
    end
    return false
end

function Planner.ChooseGoal(state, observations, construction, resourceEconomy, config)
    if #observations.threats > 0 then
        return "Flee", 100
    end

    if state.needs.energy <= config.EnergyLow then
        return "Rest", 90
    end

    if state.role == config.Roles.Gatherer then
        if state.inventory:GetTotal() > 0 and (state.inventory:IsFull() or not hasResourceKnowledge(state, observations)) then
            return "DepositResources", 95
        end

        if hasResourceKnowledge(state, observations) and not state.inventory:IsFull() then
            return "GatherResource", 90
        end

        if state.inventory:GetTotal() > 0 then
            return "DepositResources", 80
        end

        return "Explore", 40
    end

    if state.role == config.Roles.Builder then
        local active = construction.GetActive()
        if active then
            return "BuildStructure", 95
        end

        local blueprint = construction.GetNextBlueprint(state.folders, config)
        if blueprint and resourceEconomy.CanAfford(state.folders.state, blueprint.recipe) then
            return "BuildStructure", 90
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

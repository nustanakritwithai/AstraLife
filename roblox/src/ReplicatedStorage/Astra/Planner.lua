local Planner = {}

local function scoreRoleGoals(role, observations, state, worldResources, constructionAvailable)
    local scores = {
        Flee = 0,
        Rest = 0,
        GatherResource = -1000,
        BuildStructure = -1000,
        Communicate = 0,
        Explore = 10,
    }

    if #observations.threats > 0 then
        scores.Flee = 100 + (100 - state.needs.safety)
    end

    if state.needs.energy <= state.config.EnergyLow then
        scores.Rest = 80 + (state.config.EnergyLow - state.needs.energy)
    end

    if role == state.config.Roles.Scout then
        scores.Explore = 85
        if #observations.resources > 0 or #observations.agents > 0 then
            scores.Communicate = 78
        end
    elseif role == state.config.Roles.Gatherer then
        scores.Explore = 20
        if #observations.resources > 0 or state.resourceReport then
            scores.GatherResource = 96
        end
    elseif role == state.config.Roles.Builder then
        scores.Explore = 15
        if constructionAvailable and worldResources > 0 then
            scores.BuildStructure = 100
        else
            scores.Communicate = 45
        end
    else
        scores.Explore = 65
    end

    return scores
end

function Planner.ChooseGoal(role, observations, state, worldResources, constructionAvailable)
    local scores = scoreRoleGoals(role, observations, state, worldResources, constructionAvailable)
    local bestGoal = "Explore"
    local bestScore = -math.huge

    for goal, score in pairs(scores) do
        if score > bestScore then
            bestGoal = goal
            bestScore = score
        end
    end

    return bestGoal, bestScore, scores
end

function Planner.MakePlan(goal)
    if goal == "Flee" then
        return { "SelectThreat", "MoveAway" }
    elseif goal == "Rest" then
        return { "Stop", "RecoverEnergy" }
    elseif goal == "GatherResource" then
        return { "SelectResource", "MoveToResource", "CollectResource" }
    elseif goal == "BuildStructure" then
        return { "SelectBlueprint", "MoveToBuildSite", "BuildStep" }
    elseif goal == "Communicate" then
        return { "SelectMessage", "SendMessage" }
    end

    return { "Explore" }
end

return Planner

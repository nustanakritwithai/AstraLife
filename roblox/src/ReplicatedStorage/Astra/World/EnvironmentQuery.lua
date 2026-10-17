local AffordancePolicy = require(script.Parent.AffordancePolicy)

local EnvironmentQuery = {}
EnvironmentQuery.__index = EnvironmentQuery

function EnvironmentQuery.new(grid)
    assert(grid, "grid is required")
    return setmetatable({ grid = grid }, EnvironmentQuery)
end

function EnvironmentQuery:GetCellAtWorldPosition(position)
    local x, z = self.grid:WorldToCell(position)
    if not x then
        return nil
    end
    return self.grid:ReadCell(x, z)
end

function EnvironmentQuery:EvaluateActionAt(position, action, options)
    local cell = self:GetCellAtWorldPosition(position)
    local allowed, reason, facts = AffordancePolicy.Evaluate(cell, action, options)
    return {
        allowed = allowed,
        reason = reason,
        action = action,
        cell = cell,
        facts = facts,
    }
end

function EnvironmentQuery:EvaluateCellAction(x, z, action, options)
    local cell = self.grid:ReadCell(x, z)
    local allowed, reason, facts = AffordancePolicy.Evaluate(cell, action, options)
    return {
        allowed = allowed,
        reason = reason,
        action = action,
        cell = cell,
        facts = facts,
    }
end

function EnvironmentQuery:GetAffordancesAt(position)
    local cell = self:GetCellAtWorldPosition(position)
    if not cell then
        return {
            inWorld = false,
            canWalk = false,
            canDrink = false,
            canEat = false,
            canForage = false,
            canHarvestWood = false,
            canRest = false,
            canBuild = false,
            safe = false,
            reasons = {
                Walk = "outside_world",
                Drink = "outside_world",
                Eat = "outside_world",
                Forage = "outside_world",
                HarvestWood = "outside_world",
                Rest = "outside_world",
                Build = "outside_world",
            },
        }
    end

    local actions = AffordancePolicy.Snapshot(cell)
    local danger = AffordancePolicy.EffectiveDanger(cell)
    local slope = cell.slope or 0
    local food = math.max(0, cell.food or 0)
    local wood = math.max(0, cell.wood or 0)

    return {
        inWorld = true,
        canWalk = actions.Walk.allowed,
        canDrink = actions.Drink.allowed,
        canEat = actions.Eat.allowed,
        canForage = actions.Forage.allowed,
        canHarvestWood = actions.HarvestWood.allowed,
        canRest = actions.Rest.allowed,
        canBuild = actions.Build.allowed,
        safe = danger <= 0.25 and cell.hazardBlocked ~= true,
        reasons = {
            Walk = actions.Walk.reason,
            Drink = actions.Drink.reason,
            Eat = actions.Eat.reason,
            Forage = actions.Forage.reason,
            HarvestWood = actions.HarvestWood.reason,
            Rest = actions.Rest.reason,
            Build = actions.Build.reason,
        },
        danger = danger,
        baseDanger = cell.danger or 0,
        hazardDanger = cell.hazardDanger or 0,
        ecosystemDanger = cell.ecosystemDanger or 0,
        hazardBlocked = cell.hazardBlocked == true,
        dominantHazard = cell.dominantHazard or "None",
        fireIntensity = cell.fireIntensity or 0,
        floodSeverity = cell.floodSeverity or 0,
        droughtSeverity = cell.droughtSeverity or 0,
        stormSeverity = cell.stormSeverity or 0,
        herbivores = math.max(0, cell.herbivores or 0),
        predators = math.max(0, cell.predators or 0),
        scavengers = math.max(0, cell.scavengers or 0),
        carrion = math.max(0, cell.carrion or 0),
        nutrients = math.max(0, cell.nutrients or 0),
        habitatQuality = math.clamp(cell.habitatQuality or 0, 0, 1),
        biome = cell.biome,
        terrainType = cell.terrainType,
        terrainTags = cell.terrainTags,
        elevation = cell.elevation,
        height = cell.height,
        slope = slope,
        moisture = cell.moisture,
        temperature = cell.temperature,
        fertility = cell.fertility,
        waterPotential = cell.waterPotential,
        water = math.max(0, cell.water or 0),
        vegetation = cell.vegetation or 0,
        vegetationCapacity = cell.vegetationCapacity or 0,
        food = food,
        foodCapacity = cell.foodCapacity or 0,
        wood = wood,
        woodCapacity = cell.woodCapacity or 0,
        growthSuitability = cell.growthSuitability or 0,
    }
end

function EnvironmentQuery:IsWalkable(position)
    local cell = self:GetCellAtWorldPosition(position)
    if not cell then return false end
    local allowed = AffordancePolicy.Evaluate(cell, "Walk")
    return allowed == true
end

function EnvironmentQuery:IsSafe(position, maxDanger)
    local cell = self:GetCellAtWorldPosition(position)
    return cell ~= nil
        and cell.hazardBlocked ~= true
        and AffordancePolicy.EffectiveDanger(cell) <= (maxDanger or 0.25)
end

function EnvironmentQuery:FindBestCell(originPosition, radiusCells, scorer)
    assert(type(scorer) == "function", "scorer must be a function")
    local originX, originZ = self.grid:WorldToCell(originPosition)
    if not originX then
        return nil
    end

    radiusCells = math.max(0, math.floor(radiusCells or 0))
    local bestCell = nil
    local bestScore = -math.huge
    local bestDistance = math.huge

    for z = math.max(1, originZ - radiusCells), math.min(self.grid.depth, originZ + radiusCells) do
        for x = math.max(1, originX - radiusCells), math.min(self.grid.width, originX + radiusCells) do
            local cell = self.grid:ReadCell(x, z)
            local score = scorer(cell)
            if type(score) == "number" then
                local dx = x - originX
                local dz = z - originZ
                local distance = dx * dx + dz * dz
                if score > bestScore or (score == bestScore and distance < bestDistance) then
                    bestCell = cell
                    bestScore = score
                    bestDistance = distance
                end
            end
        end
    end

    if not bestCell then
        return nil
    end

    return {
        cell = bestCell,
        position = self.grid:CellCenter(bestCell.x, bestCell.z),
        score = bestScore,
        distanceSquared = bestDistance,
    }
end

return EnvironmentQuery

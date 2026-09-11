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

function EnvironmentQuery:GetAffordancesAt(position)
    local cell = self:GetCellAtWorldPosition(position)
    if not cell then
        return {
            inWorld = false,
            canWalk = false,
            canDrink = false,
            canEat = false,
            canRest = false,
            canBuild = false,
            safe = false,
        }
    end

    local safe = cell.danger <= 0.25
    return {
        inWorld = true,
        canWalk = cell.walkable == true,
        canDrink = cell.water >= 0.2,
        canEat = cell.food >= 1,
        canRest = cell.walkable == true and safe,
        canBuild = cell.walkable == true and safe and cell.water < 0.15,
        safe = safe,
        danger = cell.danger,
        biome = cell.biome,
        moisture = cell.moisture,
        temperature = cell.temperature,
    }
end

function EnvironmentQuery:IsWalkable(position)
    local cell = self:GetCellAtWorldPosition(position)
    return cell ~= nil and cell.walkable == true
end

function EnvironmentQuery:IsSafe(position, maxDanger)
    local cell = self:GetCellAtWorldPosition(position)
    return cell ~= nil and cell.danger <= (maxDanger or 0.25)
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

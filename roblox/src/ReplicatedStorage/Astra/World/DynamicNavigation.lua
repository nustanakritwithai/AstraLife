local AffordancePolicy = require(script.Parent.AffordancePolicy)

local DynamicNavigation = {}
DynamicNavigation.__index = DynamicNavigation

local CARDINAL = {
    { 0, -1 },
    { 1, 0 },
    { 0, 1 },
    { -1, 0 },
}

local DEFAULTS = {
    maxExpanded = 2048,
    maxReplans = 4,
    hazardCost = 8,
    slopeCost = 2.5,
    waterCost = 1.5,
}

local function mergeConfig(config)
    local merged = {}
    for key, value in pairs(DEFAULTS) do
        merged[key] = config and config[key] ~= nil and config[key] or value
    end
    return merged
end

local function manhattan(ax, az, bx, bz)
    return math.abs(ax - bx) + math.abs(az - bz)
end

local function cellRiskCost(cell, config)
    local danger = AffordancePolicy.EffectiveDanger(cell)
    return 1
        + danger * config.hazardCost
        + math.clamp(cell.slope or 0, 0, 1) * config.slopeCost
        + math.clamp(cell.water or 0, 0, 1) * config.waterCost
end

local function chooseBest(openList)
    local bestIndex = 1
    local best = openList[1]
    for index = 2, #openList do
        local candidate = openList[index]
        local better = candidate.f < best.f
            or (candidate.f == best.f and candidate.h < best.h)
            or (candidate.f == best.f and candidate.h == best.h and candidate.z < best.z)
            or (candidate.f == best.f and candidate.h == best.h and candidate.z == best.z and candidate.x < best.x)
        if better then
            best = candidate
            bestIndex = index
        end
    end
    return bestIndex, best
end

local function reconstruct(grid, cameFrom, goalKey)
    local reversed = {}
    local key = goalKey
    while key do
        local x, z = grid:ParseKey(key)
        local cell = grid:ReadCell(x, z)
        table.insert(reversed, {
            x = x,
            z = z,
            key = key,
            version = cell and cell.version or -1,
            hazardDanger = cell and (cell.hazardDanger or 0) or 1,
            hazardBlocked = cell ~= nil and cell.hazardBlocked == true,
        })
        key = cameFrom[key]
    end

    local path = {}
    for index = #reversed, 1, -1 do
        table.insert(path, reversed[index])
    end
    return path
end

local function hashPath(cells)
    local hash = 5381
    local modulus = 4294967296
    for _, node in ipairs(cells or {}) do
        local text = table.concat({
            tostring(node.key),
            tostring(node.version or -1),
        }, "|")
        for index = 1, #text do
            hash = (hash * 33 + string.byte(text, index)) % modulus
        end
    end
    return string.format("%08x", hash)
end

function DynamicNavigation.new(grid, config)
    assert(grid, "grid is required")
    return setmetatable({
        grid = grid,
        config = mergeConfig(config or {}),
        sequence = 0,
        stats = {
            plans = 0,
            planFailures = 0,
            replans = 0,
            invalidations = 0,
            expanded = 0,
        },
    }, DynamicNavigation)
end

function DynamicNavigation:_walkable(x, z)
    local cell = self.grid:ReadCell(x, z)
    if not cell then return false, "outside_world" end
    return AffordancePolicy.Evaluate(cell, "Walk")
end

function DynamicNavigation:PlanCells(startX, startZ, goalX, goalZ, options)
    options = options or {}
    self.sequence += 1
    self.stats.plans += 1

    if not self.grid:IsInside(startX, startZ) or not self.grid:IsInside(goalX, goalZ) then
        self.stats.planFailures += 1
        return nil, "outside_world"
    end

    local startAllowed, startReason = self:_walkable(startX, startZ)
    if not startAllowed then
        self.stats.planFailures += 1
        return nil, "start_" .. tostring(startReason)
    end
    local goalAllowed, goalReason = self:_walkable(goalX, goalZ)
    if not goalAllowed then
        self.stats.planFailures += 1
        return nil, "goal_" .. tostring(goalReason)
    end

    local startKey = self.grid:Key(startX, startZ)
    local goalKey = self.grid:Key(goalX, goalZ)
    if startKey == goalKey then
        local cells = reconstruct(self.grid, {}, goalKey)
        return {
            id = string.format("route:%d", self.sequence),
            start = { x = startX, z = startZ },
            goal = { x = goalX, z = goalZ },
            cells = cells,
            cost = 0,
            expanded = 0,
            replans = options.replans or 0,
            fingerprint = hashPath(cells),
        }, nil
    end

    local maxExpanded = math.max(1, math.floor(options.maxExpanded or self.config.maxExpanded))
    local openList = {
        {
            key = startKey,
            x = startX,
            z = startZ,
            g = 0,
            h = manhattan(startX, startZ, goalX, goalZ),
            f = manhattan(startX, startZ, goalX, goalZ),
        },
    }
    local openByKey = { [startKey] = true }
    local closed = {}
    local cameFrom = {}
    local gScore = { [startKey] = 0 }
    local expanded = 0

    while #openList > 0 and expanded < maxExpanded do
        local bestIndex, current = chooseBest(openList)
        table.remove(openList, bestIndex)
        openByKey[current.key] = nil

        if not closed[current.key] then
            closed[current.key] = true
            expanded += 1

            if current.key == goalKey then
                local cells = reconstruct(self.grid, cameFrom, goalKey)
                self.stats.expanded += expanded
                return {
                    id = string.format("route:%d", self.sequence),
                    start = { x = startX, z = startZ },
                    goal = { x = goalX, z = goalZ },
                    cells = cells,
                    cost = current.g,
                    expanded = expanded,
                    replans = options.replans or 0,
                    fingerprint = hashPath(cells),
                }, nil
            end

            for _, offset in ipairs(CARDINAL) do
                local nx = current.x + offset[1]
                local nz = current.z + offset[2]
                if self.grid:IsInside(nx, nz) then
                    local neighborKey = self.grid:Key(nx, nz)
                    if not closed[neighborKey] then
                        local allowed = self:_walkable(nx, nz)
                        if allowed then
                            local cell = self.grid:ReadCell(nx, nz)
                            local tentative = current.g + cellRiskCost(cell, self.config)
                            if tentative < (gScore[neighborKey] or math.huge) then
                                cameFrom[neighborKey] = current.key
                                gScore[neighborKey] = tentative
                                local h = manhattan(nx, nz, goalX, goalZ)
                                if not openByKey[neighborKey] then
                                    table.insert(openList, {
                                        key = neighborKey,
                                        x = nx,
                                        z = nz,
                                        g = tentative,
                                        h = h,
                                        f = tentative + h,
                                    })
                                    openByKey[neighborKey] = true
                                else
                                    for _, openNode in ipairs(openList) do
                                        if openNode.key == neighborKey then
                                            openNode.g = tentative
                                            openNode.h = h
                                            openNode.f = tentative + h
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    self.stats.expanded += expanded
    self.stats.planFailures += 1
    if expanded >= maxExpanded then
        return nil, "search_budget_exhausted"
    end
    return nil, "no_route"
end

function DynamicNavigation:PlanWorld(startPosition, goalPosition, options)
    local startX, startZ = self.grid:WorldToCell(startPosition)
    local goalX, goalZ = self.grid:WorldToCell(goalPosition)
    if not startX or not goalX then return nil, "outside_world" end
    return self:PlanCells(startX, startZ, goalX, goalZ, options)
end

function DynamicNavigation:Revalidate(path, fromIndex)
    if not path or type(path.cells) ~= "table" or #path.cells == 0 then
        return {
            valid = false,
            reason = "missing_path",
            invalidIndex = nil,
            changedCells = 0,
        }
    end

    fromIndex = math.clamp(math.floor(fromIndex or 1), 1, #path.cells)
    local changedCells = 0
    for index = fromIndex, #path.cells do
        local node = path.cells[index]
        local cell = self.grid:ReadCell(node.x, node.z)
        if not cell then
            self.stats.invalidations += 1
            return {
                valid = false,
                reason = "outside_world",
                invalidIndex = index,
                invalidKey = node.key,
                changedCells = changedCells,
            }
        end

        if (cell.version or 0) ~= (node.version or -1) then
            changedCells += 1
            local allowed, reason = AffordancePolicy.Evaluate(cell, "Walk")
            if not allowed then
                self.stats.invalidations += 1
                return {
                    valid = false,
                    reason = reason,
                    invalidIndex = index,
                    invalidKey = node.key,
                    changedCells = changedCells,
                }
            end
        end
    end

    return {
        valid = true,
        reason = changedCells > 0 and "changed_but_valid" or "unchanged",
        invalidIndex = nil,
        changedCells = changedCells,
    }
end

function DynamicNavigation:Replan(path, currentX, currentZ, options)
    options = options or {}
    local priorReplans = path and path.replans or 0
    local maxReplans = math.max(0, math.floor(options.maxReplans or self.config.maxReplans))
    if priorReplans >= maxReplans then
        return nil, "replan_budget_exhausted"
    end
    if not path or not path.goal then return nil, "missing_goal" end

    self.stats.replans += 1
    return self:PlanCells(
        currentX,
        currentZ,
        path.goal.x,
        path.goal.z,
        {
            maxExpanded = options.maxExpanded,
            replans = priorReplans + 1,
        }
    )
end

function DynamicNavigation:GetStats()
    local result = {}
    for key, value in pairs(self.stats) do result[key] = value end
    return result
end

function DynamicNavigation.PathFingerprint(path)
    return path and hashPath(path.cells) or "00000000"
end

return DynamicNavigation

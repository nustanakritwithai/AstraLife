local WorldGrid = {}
WorldGrid.__index = WorldGrid

local DEFAULT_CELL = {
    biome = "Plains",
    terrainType = "Grass",
    elevation = 0.5,
    height = 0,
    slope = 0,
    water = 0,
    moisture = 0.5,
    temperature = 0.5,
    fertility = 0.5,
    waterPotential = 0.25,
    vegetation = 0,
    vegetationCapacity = 0,
    food = 0,
    foodCapacity = 0,
    wood = 0,
    woodCapacity = 0,
    growthSuitability = 0,
    danger = 0,
    walkable = true,
}

local function cloneTags(tags)
    local result = {}
    for index, value in ipairs(tags or {}) do
        result[index] = value
    end
    return result
end

local function cloneDefault(x, z)
    return {
        x = x,
        z = z,
        biome = DEFAULT_CELL.biome,
        terrainType = DEFAULT_CELL.terrainType,
        elevation = DEFAULT_CELL.elevation,
        height = DEFAULT_CELL.height,
        slope = DEFAULT_CELL.slope,
        water = DEFAULT_CELL.water,
        moisture = DEFAULT_CELL.moisture,
        temperature = DEFAULT_CELL.temperature,
        fertility = DEFAULT_CELL.fertility,
        waterPotential = DEFAULT_CELL.waterPotential,
        vegetation = DEFAULT_CELL.vegetation,
        vegetationCapacity = DEFAULT_CELL.vegetationCapacity,
        food = DEFAULT_CELL.food,
        foodCapacity = DEFAULT_CELL.foodCapacity,
        wood = DEFAULT_CELL.wood,
        woodCapacity = DEFAULT_CELL.woodCapacity,
        growthSuitability = DEFAULT_CELL.growthSuitability,
        danger = DEFAULT_CELL.danger,
        walkable = DEFAULT_CELL.walkable,
        terrainTags = {},
        version = 0,
    }
end

function WorldGrid.new(config)
    config = config or {}
    return setmetatable({
        width = config.width or 64,
        depth = config.depth or 64,
        cellSize = config.cellSize or 16,
        origin = config.origin or Vector3.zero,
        _cells = {},
        _materialized = 0,
    }, WorldGrid)
end

function WorldGrid:Key(x, z)
    return string.format("%d:%d", x, z)
end

function WorldGrid:ParseKey(key)
    local xText, zText = string.match(tostring(key), "^(-?%d+):(-?%d+)$")
    if not xText then
        return nil, nil
    end
    return tonumber(xText), tonumber(zText)
end

function WorldGrid:IsInside(x, z)
    return x >= 1 and x <= self.width and z >= 1 and z <= self.depth
end

function WorldGrid:GetCell(x, z)
    if not self:IsInside(x, z) then
        return nil
    end

    local key = self:Key(x, z)
    local cell = self._cells[key]
    if not cell then
        cell = cloneDefault(x, z)
        self._cells[key] = cell
        self._materialized += 1
    end
    return cell
end

function WorldGrid:ReadCell(x, z)
    if not self:IsInside(x, z) then
        return nil
    end
    local existing = self._cells[self:Key(x, z)]
    return existing or cloneDefault(x, z)
end

function WorldGrid:GetCellByKey(key, create)
    local x, z = self:ParseKey(key)
    if not x then
        return nil
    end
    if create == false then
        return self:ReadCell(x, z)
    end
    return self:GetCell(x, z)
end

function WorldGrid:UpdateCell(x, z, patch, dirtyTracker)
    local cell = self:GetCell(x, z)
    if not cell then
        return nil, false
    end

    local changed = false
    for field, value in pairs(patch or {}) do
        if field ~= "x" and field ~= "z" and field ~= "version" and cell[field] ~= value then
            cell[field] = value
            changed = true
        end
    end

    if changed then
        cell.version += 1
        if dirtyTracker then
            dirtyTracker:Mark(self:Key(x, z))
        end
    end

    return cell, changed
end

function WorldGrid:WorldToCell(position)
    local localX = position.X - self.origin.X
    local localZ = position.Z - self.origin.Z
    local x = math.floor(localX / self.cellSize) + 1
    local z = math.floor(localZ / self.cellSize) + 1
    if not self:IsInside(x, z) then
        return nil, nil
    end
    return x, z
end

function WorldGrid:CellCenter(x, z, y)
    if not self:IsInside(x, z) then
        return nil
    end
    local centerY = y
    if centerY == nil then
        local cell = self:ReadCell(x, z)
        centerY = self.origin.Y + (cell and cell.height or 0)
    end
    return Vector3.new(
        self.origin.X + (x - 0.5) * self.cellSize,
        centerY,
        self.origin.Z + (z - 0.5) * self.cellSize
    )
end

function WorldGrid:GetMaterializedCount()
    return self._materialized
end

function WorldGrid:GetMaterializedKeys()
    local keys = {}
    for key in pairs(self._cells) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

function WorldGrid:SerializeCell(cell)
    if not cell then
        return nil
    end
    return {
        x = cell.x,
        z = cell.z,
        biome = cell.biome,
        terrainType = cell.terrainType,
        elevation = cell.elevation,
        height = cell.height,
        slope = cell.slope,
        water = cell.water,
        moisture = cell.moisture,
        temperature = cell.temperature,
        fertility = cell.fertility,
        waterPotential = cell.waterPotential,
        vegetation = cell.vegetation,
        vegetationCapacity = cell.vegetationCapacity,
        food = cell.food,
        foodCapacity = cell.foodCapacity,
        wood = cell.wood,
        woodCapacity = cell.woodCapacity,
        growthSuitability = cell.growthSuitability,
        danger = cell.danger,
        walkable = cell.walkable,
        terrainTags = cloneTags(cell.terrainTags),
        version = cell.version,
    }
end

return WorldGrid

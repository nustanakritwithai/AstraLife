local WorldGrid = {}
WorldGrid.__index = WorldGrid

local DEFAULT_CELL = {
    biome = "Plains",
    height = 0,
    water = 0,
    moisture = 0.5,
    temperature = 0.5,
    vegetation = 0,
    food = 0,
    danger = 0,
    walkable = true,
}

local function cloneDefault(x, z)
    return {
        x = x,
        z = z,
        biome = DEFAULT_CELL.biome,
        height = DEFAULT_CELL.height,
        water = DEFAULT_CELL.water,
        moisture = DEFAULT_CELL.moisture,
        temperature = DEFAULT_CELL.temperature,
        vegetation = DEFAULT_CELL.vegetation,
        food = DEFAULT_CELL.food,
        danger = DEFAULT_CELL.danger,
        walkable = DEFAULT_CELL.walkable,
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
    return Vector3.new(
        self.origin.X + (x - 0.5) * self.cellSize,
        y or self.origin.Y,
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
        height = cell.height,
        water = cell.water,
        moisture = cell.moisture,
        temperature = cell.temperature,
        vegetation = cell.vegetation,
        food = cell.food,
        danger = cell.danger,
        walkable = cell.walkable,
        version = cell.version,
    }
end

return WorldGrid

local WorldSimGrid = {}

WorldSimGrid.DEFAULT_CELL_SIZE = 32

function WorldSimGrid.PositionToCell(position, cellSize)
    local size = cellSize or WorldSimGrid.DEFAULT_CELL_SIZE
    return math.floor(position.X / size), math.floor(position.Z / size)
end

function WorldSimGrid.CellKey(x, z)
    return string.format("%d:%d", x, z)
end

function WorldSimGrid.PositionKey(position, cellSize)
    local x, z = WorldSimGrid.PositionToCell(position, cellSize)
    return WorldSimGrid.CellKey(x, z)
end

function WorldSimGrid.CellCenter(x, z, cellSize)
    local size = cellSize or WorldSimGrid.DEFAULT_CELL_SIZE
    return Vector3.new((x + 0.5) * size, 0, (z + 0.5) * size)
end

function WorldSimGrid.Neighborhood(x, z, radius)
    local out = {}
    local r = radius or 1
    for dz = -r, r do
        for dx = -r, r do
            table.insert(out, {
                x = x + dx,
                z = z + dz,
                key = WorldSimGrid.CellKey(x + dx, z + dz),
            })
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function WorldSimGrid.ManhattanDistance(ax, az, bx, bz)
    return math.abs(ax - bx) + math.abs(az - bz)
end

function WorldSimGrid.WorldDistanceCells(a, b, cellSize)
    local ax, az = WorldSimGrid.PositionToCell(a, cellSize)
    local bx, bz = WorldSimGrid.PositionToCell(b, cellSize)
    return WorldSimGrid.ManhattanDistance(ax, az, bx, bz)
end

return WorldSimGrid

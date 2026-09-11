local WorldSnapshot = {}

local MODULUS = 4294967296

local function hashText(text)
    local hash = 5381
    for index = 1, #text do
        hash = (hash * 33 + string.byte(text, index)) % MODULUS
    end
    return hash
end

local function boolText(value)
    return value and "1" or "0"
end

local function tagsText(tags)
    local copy = {}
    for index, value in ipairs(tags or {}) do
        copy[index] = tostring(value)
    end
    table.sort(copy)
    return table.concat(copy, ",")
end

local function cellCanonical(cell)
    return table.concat({
        tostring(cell.x), tostring(cell.z), tostring(cell.biome), tostring(cell.terrainType or ""),
        string.format("%.4f", cell.elevation or 0),
        string.format("%.4f", cell.height or 0),
        string.format("%.4f", cell.slope or 0),
        string.format("%.4f", cell.water or 0),
        string.format("%.4f", cell.moisture or 0),
        string.format("%.4f", cell.temperature or 0),
        string.format("%.4f", cell.fertility or 0),
        string.format("%.4f", cell.waterPotential or 0),
        string.format("%.4f", cell.vegetation or 0),
        string.format("%.4f", cell.vegetationCapacity or 0),
        string.format("%.4f", cell.food or 0),
        string.format("%.4f", cell.foodCapacity or 0),
        string.format("%.4f", cell.wood or 0),
        string.format("%.4f", cell.woodCapacity or 0),
        string.format("%.4f", cell.growthSuitability or 0),
        string.format("%.4f", cell.fireIntensity or 0),
        string.format("%.4f", cell.floodSeverity or 0),
        string.format("%.4f", cell.droughtSeverity or 0),
        string.format("%.4f", cell.stormSeverity or 0),
        string.format("%.4f", cell.hazardDanger or 0),
        boolText(cell.hazardBlocked == true),
        tostring(cell.dominantHazard or "None"),
        string.format("%.4f", cell.danger or 0),
        boolText(cell.walkable == true),
        tagsText(cell.terrainTags),
        tostring(cell.version or 0),
    }, "|")
end

function WorldSnapshot.BuildDelta(meta, grid, dirtyEntries)
    local snapshot = {
        version = meta.version or "W0",
        seed = meta.seed,
        tick = meta.tick,
        simTime = meta.simTime,
        cells = {},
    }

    for _, entry in ipairs(dirtyEntries or {}) do
        local cell = grid:GetCellByKey(entry.key, false)
        if cell then
            snapshot.cells[entry.key] = grid:SerializeCell(cell)
        end
    end

    snapshot.fingerprint = WorldSnapshot.Fingerprint(snapshot)
    return snapshot
end

function WorldSnapshot.BuildFull(meta, grid)
    local entries = {}
    for _, key in ipairs(grid:GetMaterializedKeys()) do
        table.insert(entries, { key = key })
    end
    return WorldSnapshot.BuildDelta(meta, grid, entries)
end

function WorldSnapshot.Fingerprint(snapshot)
    local pieces = {
        tostring(snapshot.version or ""),
        tostring(snapshot.seed or ""),
        tostring(snapshot.tick or 0),
        string.format("%.4f", snapshot.simTime or 0),
    }

    local keys = {}
    for key in pairs(snapshot.cells or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        table.insert(pieces, key)
        table.insert(pieces, cellCanonical(snapshot.cells[key]))
    end

    return string.format("%08x", hashText(table.concat(pieces, "#")))
end

return WorldSnapshot

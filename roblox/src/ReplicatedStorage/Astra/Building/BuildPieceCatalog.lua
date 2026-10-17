-- B0 Modular Building Foundation
-- Data-only piece definitions. No P3 Construction.lua dependency.

local BuildPieceCatalog = {}

local DEFINITIONS = {
    FoundationSquare = {
        category = "Foundation",
        size = Vector3.new(12, 1, 12),
        grounded = true,
        stabilityTransfer = 1.00,
        minStability = 0.95,
        cost = { Wood = 20 },
        connectors = {
            { name = "FoundationNorth", kind = "FoundationEdge", localCFrame = CFrame.new(0, 0, -6) * CFrame.Angles(0, math.rad(180), 0) },
            { name = "FoundationEast", kind = "FoundationEdge", localCFrame = CFrame.new(6, 0, 0) * CFrame.Angles(0, math.rad(-90), 0) },
            { name = "FoundationSouth", kind = "FoundationEdge", localCFrame = CFrame.new(0, 0, 6) },
            { name = "FoundationWest", kind = "FoundationEdge", localCFrame = CFrame.new(-6, 0, 0) * CFrame.Angles(0, math.rad(90), 0) },
            { name = "WallNorth", kind = "WallEdge", localCFrame = CFrame.new(0, 0.5, -6) * CFrame.Angles(0, math.rad(180), 0) },
            { name = "WallEast", kind = "WallEdge", localCFrame = CFrame.new(6, 0.5, 0) * CFrame.Angles(0, math.rad(-90), 0) },
            { name = "WallSouth", kind = "WallEdge", localCFrame = CFrame.new(0, 0.5, 6) },
            { name = "WallWest", kind = "WallEdge", localCFrame = CFrame.new(-6, 0.5, 0) * CFrame.Angles(0, math.rad(90), 0) },
            { name = "Interior", kind = "InteriorFloor", localCFrame = CFrame.new(0, 0.5, 0) },
        },
        attachments = {
            { name = "Edge", accepts = { "FoundationEdge" }, localCFrame = CFrame.new(0, 0, 6) },
        },
    },

    FoundationTriangle = {
        category = "Foundation",
        size = Vector3.new(12, 1, 10.4),
        grounded = true,
        stabilityTransfer = 1.00,
        minStability = 0.95,
        cost = { Wood = 15 },
        connectors = {
            { name = "EdgeA", kind = "FoundationEdge", localCFrame = CFrame.new(0, 0, 5.2) },
            { name = "EdgeB", kind = "FoundationEdge", localCFrame = CFrame.new(-4.5, 0, -2.6) * CFrame.Angles(0, math.rad(120), 0) },
            { name = "EdgeC", kind = "FoundationEdge", localCFrame = CFrame.new(4.5, 0, -2.6) * CFrame.Angles(0, math.rad(-120), 0) },
            { name = "WallA", kind = "WallEdge", localCFrame = CFrame.new(0, 0.5, 5.2) },
            { name = "WallB", kind = "WallEdge", localCFrame = CFrame.new(-4.5, 0.5, -2.6) * CFrame.Angles(0, math.rad(120), 0) },
            { name = "WallC", kind = "WallEdge", localCFrame = CFrame.new(4.5, 0.5, -2.6) * CFrame.Angles(0, math.rad(-120), 0) },
        },
        attachments = {
            { name = "Edge", accepts = { "FoundationEdge" }, localCFrame = CFrame.new(0, 0, 5.2) },
        },
    },

    Wall = {
        category = "Wall",
        size = Vector3.new(12, 8, 0.6),
        grounded = false,
        stabilityTransfer = 0.82,
        minStability = 0.30,
        cost = { Wood = 10 },
        connectors = {
            { name = "Top", kind = "WallTop", localCFrame = CFrame.new(0, 8, 0) },
            { name = "UpperWall", kind = "WallEdge", localCFrame = CFrame.new(0, 8, 0) },
        },
        attachments = {
            { name = "Bottom", accepts = { "WallEdge" }, localCFrame = CFrame.new(0, 0, 0) },
        },
    },

    HalfWall = {
        category = "Wall",
        size = Vector3.new(12, 4, 0.6),
        grounded = false,
        stabilityTransfer = 0.87,
        minStability = 0.35,
        cost = { Wood = 6 },
        connectors = {
            { name = "Top", kind = "WallTop", localCFrame = CFrame.new(0, 4, 0) },
            { name = "UpperWall", kind = "WallEdge", localCFrame = CFrame.new(0, 4, 0) },
        },
        attachments = {
            { name = "Bottom", accepts = { "WallEdge" }, localCFrame = CFrame.new(0, 0, 0) },
        },
    },

    DoorFrame = {
        category = "Wall",
        size = Vector3.new(12, 8, 0.6),
        grounded = false,
        stabilityTransfer = 0.80,
        minStability = 0.30,
        cost = { Wood = 12 },
        connectors = {
            { name = "Top", kind = "WallTop", localCFrame = CFrame.new(0, 8, 0) },
            { name = "Door", kind = "DoorMount", localCFrame = CFrame.new(0, 4, 0) },
        },
        attachments = {
            { name = "Bottom", accepts = { "WallEdge" }, localCFrame = CFrame.new(0, 0, 0) },
        },
    },

    WindowFrame = {
        category = "Wall",
        size = Vector3.new(12, 8, 0.6),
        grounded = false,
        stabilityTransfer = 0.80,
        minStability = 0.30,
        cost = { Wood = 12 },
        connectors = {
            { name = "Top", kind = "WallTop", localCFrame = CFrame.new(0, 8, 0) },
            { name = "Window", kind = "WindowMount", localCFrame = CFrame.new(0, 4, 0) },
        },
        attachments = {
            { name = "Bottom", accepts = { "WallEdge" }, localCFrame = CFrame.new(0, 0, 0) },
        },
    },

    FloorSquare = {
        category = "Floor",
        size = Vector3.new(12, 0.6, 12),
        grounded = false,
        stabilityTransfer = 0.72,
        minStability = 0.22,
        cost = { Wood = 12 },
        connectors = {
            { name = "WallNorth", kind = "WallEdge", localCFrame = CFrame.new(0, 0.3, -6) * CFrame.Angles(0, math.rad(180), 0) },
            { name = "WallEast", kind = "WallEdge", localCFrame = CFrame.new(6, 0.3, 0) * CFrame.Angles(0, math.rad(-90), 0) },
            { name = "WallSouth", kind = "WallEdge", localCFrame = CFrame.new(0, 0.3, 6) },
            { name = "WallWest", kind = "WallEdge", localCFrame = CFrame.new(-6, 0.3, 0) * CFrame.Angles(0, math.rad(90), 0) },
            { name = "FloorNorth", kind = "FloorEdge", localCFrame = CFrame.new(0, 0, -6) * CFrame.Angles(0, math.rad(180), 0) },
            { name = "FloorEast", kind = "FloorEdge", localCFrame = CFrame.new(6, 0, 0) * CFrame.Angles(0, math.rad(-90), 0) },
            { name = "FloorSouth", kind = "FloorEdge", localCFrame = CFrame.new(0, 0, 6) },
            { name = "FloorWest", kind = "FloorEdge", localCFrame = CFrame.new(-6, 0, 0) * CFrame.Angles(0, math.rad(90), 0) },
            { name = "Interior", kind = "InteriorFloor", localCFrame = CFrame.new(0, 0.3, 0) },
        },
        attachments = {
            { name = "WallTop", accepts = { "WallTop" }, localCFrame = CFrame.new(0, 0, -6) },
            { name = "Edge", accepts = { "FloorEdge" }, localCFrame = CFrame.new(0, 0, 6) },
        },
    },

    FloorTriangle = {
        category = "Floor",
        size = Vector3.new(12, 0.6, 10.4),
        grounded = false,
        stabilityTransfer = 0.74,
        minStability = 0.22,
        cost = { Wood = 9 },
        connectors = {
            { name = "EdgeA", kind = "FloorEdge", localCFrame = CFrame.new(0, 0, 5.2) },
            { name = "EdgeB", kind = "FloorEdge", localCFrame = CFrame.new(-4.5, 0, -2.6) * CFrame.Angles(0, math.rad(120), 0) },
            { name = "EdgeC", kind = "FloorEdge", localCFrame = CFrame.new(4.5, 0, -2.6) * CFrame.Angles(0, math.rad(-120), 0) },
        },
        attachments = {
            { name = "WallTop", accepts = { "WallTop" }, localCFrame = CFrame.new(0, 0, -5.2) },
            { name = "Edge", accepts = { "FloorEdge" }, localCFrame = CFrame.new(0, 0, 5.2) },
        },
    },

    Roof = {
        category = "Roof",
        size = Vector3.new(12, 0.6, 12),
        grounded = false,
        stabilityTransfer = 0.68,
        minStability = 0.25,
        cost = { Wood = 12 },
        attachments = {
            { name = "WallTop", accepts = { "WallTop" }, localCFrame = CFrame.new(0, 0, -6) },
        },
        connectors = {},
    },

    Stairs = {
        category = "Stairs",
        size = Vector3.new(6, 8, 10),
        grounded = false,
        stabilityTransfer = 0.78,
        minStability = 0.30,
        cost = { Wood = 10 },
        attachments = {
            { name = "Interior", accepts = { "InteriorFloor" }, localCFrame = CFrame.new(0, 0, 0) },
        },
        connectors = {
            { name = "Landing", kind = "WallTop", localCFrame = CFrame.new(0, 8, -4) },
        },
    },
}

local function cloneList(list)
    local result = {}
    for index, entry in ipairs(list or {}) do
        local copy = {}
        for key, value in pairs(entry) do
            if type(value) == "table" then
                local nested = {}
                for nestedIndex, nestedValue in ipairs(value) do nested[nestedIndex] = nestedValue end
                copy[key] = nested
            else
                copy[key] = value
            end
        end
        result[index] = copy
    end
    return result
end

local function cloneDefinition(definition)
    if not definition then return nil end
    local result = {}
    for key, value in pairs(definition) do
        if key == "connectors" or key == "attachments" then
            result[key] = cloneList(value)
        elseif type(value) == "table" then
            local copy = {}
            for childKey, childValue in pairs(value) do copy[childKey] = childValue end
            result[key] = copy
        else
            result[key] = value
        end
    end
    return result
end

function BuildPieceCatalog.Get(pieceType)
    return cloneDefinition(DEFINITIONS[pieceType])
end

function BuildPieceCatalog.Has(pieceType)
    return DEFINITIONS[pieceType] ~= nil
end

function BuildPieceCatalog.Types()
    local result = {}
    for pieceType in pairs(DEFINITIONS) do table.insert(result, pieceType) end
    table.sort(result)
    return result
end

return BuildPieceCatalog

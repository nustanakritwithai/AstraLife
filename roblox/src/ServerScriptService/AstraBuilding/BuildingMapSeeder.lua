local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local BuildingModules = Astra:WaitForChild("Building")
local BuildPieceCatalog = require(BuildingModules.BuildPieceCatalog)
local BuildingLifecycleService = require(script.Parent.BuildingLifecycleService)
local SurfaceResolver = require(BuildingModules.SurfaceResolver)

local BuildingMapSeeder = {}

local started = false
local result = nil

local FALLBACK_ORIGIN = Vector3.new(28, 0, -4)
local SEARCH_STEP = 8
local SEARCH_RADIUS = 40
local STRUCTURE_NAME = "ModularOutpost"

local function preferredOrigin()
    local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
    if spawn then
        return Vector3.new(spawn.Position.X + 30, 0, spawn.Position.Z + 18)
    end
    return FALLBACK_ORIGIN
end

local function metadata(grade)
    return {
        materialGrade = grade,
        source = "map_seed",
        structure = STRUCTURE_NAME,
    }
end

local function physicalGroundTopY(current, position)
    return SurfaceResolver.TopY(position, {
        exclude = { current.renderFolder },
    })
end

local function moveInstance(instance, delta)
    if not instance or math.abs(delta.Y) < 1e-6 then return end
    if instance:IsA("Model") then
        instance:PivotTo(instance:GetPivot() + delta)
    elseif instance:IsA("BasePart") then
        instance.CFrame = instance.CFrame + delta
    end
end

local function findRenderedPiece(renderFolder, pieceId)
    for _, child in ipairs(renderFolder:GetChildren()) do
        if child:GetAttribute("PieceId") == pieceId then
            return child
        end
    end
    return nil
end

local function alignRootToPhysicalMap(current, piece)
    local definition = BuildPieceCatalog.Get(piece.pieceType)
    local halfHeight = definition and definition.size.Y * 0.5 or 0.5
    local desiredCenterY = physicalGroundTopY(current, piece.cframe.Position) + halfHeight
    local deltaY = desiredCenterY - piece.cframe.Position.Y
    if math.abs(deltaY) < 1e-5 then return end

    local delta = Vector3.new(0, deltaY, 0)
    piece.cframe = piece.cframe + delta
    for _, socket in pairs(piece.sockets or {}) do
        socket.worldCFrame = socket.worldCFrame + delta
    end
    moveInstance(findRenderedPiece(current.renderFolder, piece.id), delta)
end

local function candidateOffsets()
    local offsets = { Vector2.new(0, 0) }
    for radius = SEARCH_STEP, SEARCH_RADIUS, SEARCH_STEP do
        for x = -radius, radius, SEARCH_STEP do
            table.insert(offsets, Vector2.new(x, -radius))
            table.insert(offsets, Vector2.new(x, radius))
        end
        for z = -radius + SEARCH_STEP, radius - SEARCH_STEP, SEARCH_STEP do
            table.insert(offsets, Vector2.new(-radius, z))
            table.insert(offsets, Vector2.new(radius, z))
        end
    end
    return offsets
end

local function findBuildSite()
    local origin = preferredOrigin()
    for _, offset in ipairs(candidateOffsets()) do
        local position = origin + Vector3.new(offset.X, 0, offset.Y)
        local preview = BuildingLifecycleService.PreviewRoot("FoundationSquare", position, 0)
        if preview and preview.allowed then
            return position
        end
    end
    return nil
end

local function placeRequired(pieceType, parent, socketName, attachmentName, grade, failures, created)
    if not parent then return nil end
    local piece, reason = BuildingLifecycleService.PlaceSnap(
        pieceType,
        parent.id,
        socketName,
        attachmentName,
        metadata(grade)
    )
    if not piece then
        table.insert(failures, string.format("%s@%s:%s", pieceType, socketName, tostring(reason)))
        return nil
    end
    table.insert(created, piece.id)
    return piece
end

function BuildingMapSeeder.Start()
    if started then return result end
    started = true

    local current = BuildingLifecycleService.Start()
    local state = current.state

    if current.graph:Count() > 0 then
        state:SetAttribute("MapIntegrationStatus", "EXISTING")
        state:SetAttribute("MapSeeded", false)
        result = {
            seeded = false,
            reason = "existing_building_graph",
            pieceCount = current.graph:Count(),
            createdPieceIds = {},
        }
        return result
    end

    state:SetAttribute("MapIntegrationStatus", "SEARCHING")
    local position = findBuildSite()
    if not position then
        state:SetAttribute("MapIntegrationStatus", "NO_BUILD_SITE")
        state:SetAttribute("MapSeeded", false)
        result = {
            seeded = false,
            reason = "no_buildable_site",
            pieceCount = 0,
            createdPieceIds = {},
        }
        return result
    end

    local failures = {}
    local created = {}
    local root, rootReason = BuildingLifecycleService.PlaceRoot(
        "FoundationSquare",
        position,
        0,
        metadata("Stone")
    )
    if not root then
        state:SetAttribute("MapIntegrationStatus", "ROOT_FAILED")
        state:SetAttribute("MapIntegrationReason", tostring(rootReason))
        state:SetAttribute("MapSeeded", false)
        result = {
            seeded = false,
            reason = rootReason,
            pieceCount = 0,
            createdPieceIds = created,
        }
        return result
    end

    table.insert(created, root.id)
    alignRootToPhysicalMap(current, root)

    local east = placeRequired(
        "FoundationSquare", root, "FoundationEast", "Edge", "Stone", failures, created
    )

    local rootNorth = placeRequired(
        "Wall", root, "WallNorth", "Bottom", "Wood", failures, created
    )
    placeRequired(
        "Wall", root, "WallWest", "Bottom", "Wood", failures, created
    )
    placeRequired(
        "DoorFrame", root, "WallSouth", "Bottom", "Wood", failures, created
    )
    placeRequired(
        "Stairs", root, "Interior", "Interior", "Wood", failures, created
    )

    if rootNorth then
        placeRequired(
            "Roof", rootNorth, "Top", "WallTop", "Stone", failures, created
        )
    end

    if east then
        local eastNorth = placeRequired(
            "Wall", east, "WallNorth", "Bottom", "Wood", failures, created
        )
        placeRequired(
            "Wall", east, "WallSouth", "Bottom", "Wood", failures, created
        )
        placeRequired(
            "WindowFrame", east, "WallEast", "Bottom", "Stone", failures, created
        )
        if eastNorth then
            placeRequired(
                "Roof", eastNorth, "Top", "WallTop", "Stone", failures, created
            )
        end
    end

    local pieceCount = current.graph:Count()
    local origin = root.cframe.Position
    local ready = #failures == 0 and pieceCount >= 10

    state:SetAttribute("MapSeeded", true)
    state:SetAttribute("MapIntegrationStatus", ready and "READY" or "PARTIAL")
    state:SetAttribute("MapIntegrationReason", #failures == 0 and "ok" or table.concat(failures, ";"))
    state:SetAttribute("MapSeedOrigin", origin)
    state:SetAttribute("MapSeedPieceCount", pieceCount)
    state:SetAttribute("MapSeedFailureCount", #failures)
    state:SetAttribute("MapSeedStructure", STRUCTURE_NAME)
    state:SetAttribute("MapSeedVisibleTarget", true)

    if current.runtime and current.runtime.events then
        current.runtime.events:Emit("building.map.seeded", {
            structure = STRUCTURE_NAME,
            origin = origin,
            pieces = pieceCount,
            failures = failures,
        }, current.runtime.clock.tick)
    end

    result = {
        seeded = true,
        reason = ready and "ok" or "partial",
        pieceCount = pieceCount,
        origin = origin,
        failures = failures,
        root = root,
        createdPieceIds = created,
    }
    return result
end

function BuildingMapSeeder.GetResult()
    return result
end

return BuildingMapSeeder

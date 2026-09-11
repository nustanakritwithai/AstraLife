local Workspace = game:GetService("Workspace")

local BuildingLifecycleService = require(script.Parent.BuildingLifecycleService)

local BuildingMapSeeder = {}

local started = false
local result = nil

local PREFERRED_ORIGIN = Vector3.new(48, 0, 34)
local SEARCH_STEP = 8
local SEARCH_RADIUS = 48

local function physicalGroundTopY(position)
    local baseplate = Workspace:FindFirstChild("AstraBaseplate")
    if baseplate and baseplate:IsA("BasePart") then
        local localPoint = baseplate.CFrame:PointToObjectSpace(Vector3.new(
            position.X,
            baseplate.Position.Y,
            position.Z
        ))
        if math.abs(localPoint.X) <= baseplate.Size.X * 0.5
            and math.abs(localPoint.Z) <= baseplate.Size.Z * 0.5
        then
            return baseplate.Position.Y + baseplate.Size.Y * 0.5
        end
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local buildings = Workspace:FindFirstChild("AstraModularBuildings")
    params.FilterDescendantsInstances = buildings and { buildings } or {}

    local hit = Workspace:Raycast(
        Vector3.new(position.X, 256, position.Z),
        Vector3.new(0, -512, 0),
        params
    )
    if hit then
        return hit.Position.Y
    end
    return 0
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
    local definitionHeight = 1
    local desiredCenterY = physicalGroundTopY(piece.cframe.Position) + definitionHeight * 0.5
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
    local resultOffsets = { Vector2.new(0, 0) }
    for radius = SEARCH_STEP, SEARCH_RADIUS, SEARCH_STEP do
        for x = -radius, radius, SEARCH_STEP do
            table.insert(resultOffsets, Vector2.new(x, -radius))
            table.insert(resultOffsets, Vector2.new(x, radius))
        end
        for z = -radius + SEARCH_STEP, radius - SEARCH_STEP, SEARCH_STEP do
            table.insert(resultOffsets, Vector2.new(-radius, z))
            table.insert(resultOffsets, Vector2.new(radius, z))
        end
    end
    return resultOffsets
end

local function findBuildSite()
    for _, offset in ipairs(candidateOffsets()) do
        local position = PREFERRED_ORIGIN + Vector3.new(offset.X, 0, offset.Y)
        local preview = BuildingLifecycleService.PreviewRoot("FoundationSquare", position, 0)
        if preview and preview.allowed then
            return position, preview
        end
    end
    return nil, nil
end

local function placeRequired(pieceType, parent, socketName, attachmentName, metadata, failures)
    local piece, reason = BuildingLifecycleService.PlaceSnap(
        pieceType,
        parent.id,
        socketName,
        attachmentName,
        metadata
    )
    if not piece then
        table.insert(failures, string.format("%s@%s:%s", pieceType, socketName, tostring(reason)))
    end
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
        }
        return result
    end

    local failures = {}
    local root, rootReason = BuildingLifecycleService.PlaceRoot(
        "FoundationSquare",
        position,
        0,
        {
            materialGrade = "Stone",
            source = "map_seed",
            structure = "ModularOutpost",
        }
    )
    if not root then
        state:SetAttribute("MapIntegrationStatus", "ROOT_FAILED")
        state:SetAttribute("MapIntegrationReason", tostring(rootReason))
        state:SetAttribute("MapSeeded", false)
        result = {
            seeded = false,
            reason = rootReason,
            pieceCount = 0,
        }
        return result
    end

    -- B0 uses logical-world height for validation. The current playable map is a
    -- physical AstraBaseplate, so align the authoritative root + sockets to the
    -- actual map surface before snapping descendants.
    alignRootToPhysicalMap(current, root)

    local east = placeRequired(
        "FoundationSquare",
        root,
        "FoundationEast",
        "Edge",
        { materialGrade = "Stone", source = "map_seed", structure = "ModularOutpost" },
        failures
    )

    placeRequired(
        "Wall",
        root,
        "WallNorth",
        "Bottom",
        { materialGrade = "Wood", source = "map_seed", structure = "ModularOutpost" },
        failures
    )
    placeRequired(
        "Wall",
        root,
        "WallWest",
        "Bottom",
        { materialGrade = "Wood", source = "map_seed", structure = "ModularOutpost" },
        failures
    )
    placeRequired(
        "DoorFrame",
        root,
        "WallSouth",
        "Bottom",
        { materialGrade = "Wood", source = "map_seed", structure = "ModularOutpost" },
        failures
    )
    placeRequired(
        "Stairs",
        root,
        "Interior",
        "Interior",
        { materialGrade = "Wood", source = "map_seed", structure = "ModularOutpost" },
        failures
    )

    if east then
        placeRequired(
            "Wall",
            east,
            "WallNorth",
            "Bottom",
            { materialGrade = "Wood", source = "map_seed", structure = "ModularOutpost" },
            failures
        )
        placeRequired(
            "Wall",
            east,
            "WallSouth",
            "Bottom",
            { materialGrade = "Wood", source = "map_seed", structure = "ModularOutpost" },
            failures
        )
        placeRequired(
            "WindowFrame",
            east,
            "WallEast",
            "Bottom",
            { materialGrade = "Stone", source = "map_seed", structure = "ModularOutpost" },
            failures
        )
    end

    local pieceCount = current.graph:Count()
    local origin = root.cframe.Position
    state:SetAttribute("MapSeeded", true)
    state:SetAttribute("MapIntegrationStatus", #failures == 0 and "READY" or "PARTIAL")
    state:SetAttribute("MapIntegrationReason", #failures == 0 and "ok" or table.concat(failures, ";"))
    state:SetAttribute("MapSeedOrigin", origin)
    state:SetAttribute("MapSeedPieceCount", pieceCount)
    state:SetAttribute("MapSeedFailureCount", #failures)
    state:SetAttribute("MapSeedStructure", "ModularOutpost")

    if current.runtime and current.runtime.events then
        current.runtime.events:Emit("building.map.seeded", {
            structure = "ModularOutpost",
            origin = origin,
            pieces = pieceCount,
            failures = failures,
        }, current.runtime.clock.tick)
    end

    result = {
        seeded = true,
        reason = #failures == 0 and "ok" or "partial",
        pieceCount = pieceCount,
        origin = origin,
        failures = failures,
        root = root,
    }
    return result
end

function BuildingMapSeeder.GetResult()
    return result
end

return BuildingMapSeeder

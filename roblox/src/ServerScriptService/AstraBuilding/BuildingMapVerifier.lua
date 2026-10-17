local Workspace = game:GetService("Workspace")

local BuildingLifecycleService = require(script.Parent.BuildingLifecycleService)

local BuildingMapVerifier = {}

local REQUIRED_TYPES = {
    FoundationSquare = 2,
    DoorFrame = 1,
    WindowFrame = 1,
    Stairs = 1,
    Roof = 2,
}

local function findRendered(renderFolder, pieceId)
    for _, child in ipairs(renderFolder:GetChildren()) do
        if child:GetAttribute("PieceId") == pieceId then
            return child
        end
    end
    return nil
end

local function baseplateTopY()
    local baseplate = Workspace:FindFirstChild("AstraBaseplate")
    if baseplate and baseplate:IsA("BasePart") then
        return baseplate.Position.Y + baseplate.Size.Y * 0.5
    end
    return nil
end

local function countTypes(graph)
    local counts = {}
    for _, piece in pairs(graph.pieces) do
        counts[piece.pieceType] = (counts[piece.pieceType] or 0) + 1
    end
    return counts
end

function BuildingMapVerifier.Run(seedResult)
    local current = BuildingLifecycleService.Start()
    local graph = current.graph
    local renderFolder = current.renderFolder
    local state = current.state
    local checks = {}

    checks.seeded = seedResult and seedResult.seeded == true
    checks.minimumPieceCount = graph:Count() >= 10
    checks.renderCountMatchesGraph = #renderFolder:GetChildren() == graph:Count()

    local counts = countTypes(graph)
    local requiredTypes = true
    for pieceType, minimum in pairs(REQUIRED_TYPES) do
        if (counts[pieceType] or 0) < minimum then
            requiredTypes = false
            break
        end
    end
    checks.requiredVisibleTypes = requiredTypes

    local allRendered = true
    local lifecycleVisible = true
    local allSeedMetadata = true
    for pieceId, piece in pairs(graph.pieces) do
        local instance = findRendered(renderFolder, pieceId)
        if not instance then
            allRendered = false
        else
            local grade = instance:GetAttribute("MaterialGrade")
            local health = instance:GetAttribute("Health")
            local maxHealth = instance:GetAttribute("MaxHealth")
            if type(grade) ~= "string"
                or type(health) ~= "number"
                or type(maxHealth) ~= "number"
                or maxHealth <= 0
                or health < 0
                or health > maxHealth
            then
                lifecycleVisible = false
            end
        end

        local metadata = piece.metadata or {}
        if metadata.source ~= "map_seed" or metadata.structure ~= "ModularOutpost" then
            allSeedMetadata = false
        end
    end
    checks.allGraphPiecesRendered = allRendered
    checks.lifecycleAttributesRendered = lifecycleVisible
    checks.seedMetadataConsistent = allSeedMetadata

    local root = seedResult and seedResult.root or nil
    local groundTop = baseplateTopY()
    if root and groundTop then
        checks.rootAlignedToPhysicalGround = math.abs(root.cframe.Position.Y - (groundTop + 0.5)) <= 0.05
    else
        checks.rootAlignedToPhysicalGround = root ~= nil
    end

    local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
    if spawn and root then
        local horizontal = Vector3.new(
            root.cframe.Position.X - spawn.Position.X,
            0,
            root.cframe.Position.Z - spawn.Position.Z
        ).Magnitude
        checks.visibleNearStart = horizontal <= 64
        state:SetAttribute("MapRuntimeDistanceFromSpawn", horizontal)
    else
        checks.visibleNearStart = root ~= nil
    end

    local passed = true
    for _, value in pairs(checks) do
        if value ~= true then
            passed = false
            break
        end
    end

    state:SetAttribute("MapRuntimeStatus", passed and "PASS" or "FAIL")
    state:SetAttribute("MapRuntimeGraphCount", graph:Count())
    state:SetAttribute("MapRuntimeRenderCount", #renderFolder:GetChildren())
    for name, value in pairs(checks) do
        state:SetAttribute("MapRuntimeCheck_" .. name, value)
    end

    return passed, checks, {
        graphCount = graph:Count(),
        renderCount = #renderFolder:GetChildren(),
        counts = counts,
    }
end

return BuildingMapVerifier

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local BuildingModules = Astra:WaitForChild("Building")
local BuildPieceCatalog = require(BuildingModules.BuildPieceCatalog)
local BuildGraph = require(BuildingModules.BuildGraph)
local PlacementValidator = require(BuildingModules.PlacementValidator)
local PieceRenderer = require(BuildingModules.PieceRenderer)
local B0Verifier = require(BuildingModules.B0Verifier)

local AstraWorldFolder = script.Parent.Parent:WaitForChild("AstraWorld")
local EcosystemService = require(AstraWorldFolder:WaitForChild("EcosystemService"))

local ModularBuildingService = {}

local started = false
local result = nil
local instances = {}

local function ensureFolder(name)
    local existing = Workspace:FindFirstChild(name)
    if existing then return existing end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = Workspace
    return folder
end

local function boundsCFrame(pieceType, cframe)
    if pieceType == "Wall" or pieceType == "DoorFrame" or pieceType == "WindowFrame" then
        return cframe * CFrame.new(0, 4, 0)
    elseif pieceType == "HalfWall" then
        return cframe * CFrame.new(0, 2, 0)
    elseif pieceType == "Stairs" then
        return cframe * CFrame.new(0, 4, 0)
    end
    return cframe
end

local function collisionCheckFactory(renderFolder)
    return function(pieceType, cframe, size, context)
        local boxCFrame = boundsCFrame(pieceType, cframe)
        local shrink = Vector3.new(
            math.max(0.1, size.X * 0.90),
            math.max(0.1, size.Y * 0.90),
            math.max(0.1, size.Z * 0.90)
        )
        local overlaps = Workspace:GetPartBoundsInBox(boxCFrame, shrink)
        for _, part in ipairs(overlaps) do
            if part:IsA("BasePart") then
                if part:IsDescendantOf(renderFolder) then
                    local pieceId = part:GetAttribute("PieceId")
                    if pieceId ~= context.parentId then
                        return false, "building_overlap"
                    end
                elseif part:GetAttribute("BuildBlocksPlacement") == true then
                    return false, "world_obstacle"
                end
            end
        end
        return true, "ok"
    end
end

local function publishState(current, action, reason, collapsed)
    local state = current.state
    state:SetAttribute("Version", "B0")
    state:SetAttribute("PieceCount", current.graph:Count())
    state:SetAttribute("GraphFingerprint", current.graph:Fingerprint())
    state:SetAttribute("LastAction", tostring(action or "none"))
    state:SetAttribute("LastReason", tostring(reason or "ok"))
    state:SetAttribute("LastCollapsedCount", collapsed or 0)
end

local function emit(current, eventType, payload)
    if current.runtime and current.runtime.events then
        current.runtime.events:Emit(eventType, payload, current.runtime.clock.tick)
    end
end

local function renderPiece(current, piece)
    local instance = PieceRenderer.Create(piece)
    instance.Parent = current.renderFolder
    instances[piece.id] = instance
    return instance
end

local function destroyPieceInstance(pieceId)
    local instance = instances[pieceId]
    if instance and instance.Parent then instance:Destroy() end
    instances[pieceId] = nil
end

local function refreshStability(current)
    local unstable = current.graph:RecomputeStability()
    for pieceId, piece in pairs(current.graph.pieces) do
        PieceRenderer.UpdateStability(instances[pieceId], piece.stability)
    end
    return unstable
end

local function collapseUnstable(current, initial)
    local queue = {}
    local seen = {}
    for _, id in ipairs(initial or {}) do table.insert(queue, id) end
    local collapsed = {}

    local index = 1
    while index <= #queue do
        local pieceId = queue[index]
        index += 1
        if not seen[pieceId] and current.graph:Get(pieceId) then
            seen[pieceId] = true
            local _, newlyUnstable = current.graph:Remove(pieceId)
            destroyPieceInstance(pieceId)
            table.insert(collapsed, pieceId)
            for _, nextId in ipairs(newlyUnstable or {}) do
                if not seen[nextId] then table.insert(queue, nextId) end
            end
        end
    end

    refreshStability(current)
    table.sort(collapsed)
    return collapsed
end

function ModularBuildingService.Start()
    if started then return result end
    started = true

    local ecosystemResult = EcosystemService.Start()
    local runtime = ecosystemResult.runtime
    local state = ensureFolder("AstraBuildingState")
    local renderFolder = ensureFolder("AstraModularBuildings")

    local graph = BuildGraph.new()
    local validator = PlacementValidator.new(graph, {
        environmentQuery = runtime.query,
        collisionCheck = collisionCheckFactory(renderFolder),
        maxPieces = 512,
        rootGrid = 2,
        rootYawStep = 90,
        maxRootSlope = 0.35,
    })

    local passed, checks, verifierStats = B0Verifier.Run()
    state:SetAttribute("B0Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("B0Check_" .. name, value)
    end
    state:SetAttribute("B0VerifierFingerprint", verifierStats.fingerprint)
    state:SetAttribute("B0VerifierPieceTypes", verifierStats.pieceTypes)
    state:SetAttribute("B0VerifierUnstable", verifierStats.unstableAfterRootRemoval)
    state:SetAttribute("MaxPieces", validator.config.maxPieces)

    result = {
        runtime = runtime,
        state = state,
        renderFolder = renderFolder,
        graph = graph,
        validator = validator,
        passed = passed,
        checks = checks,
    }
    publishState(result, "start", "ok", 0)

    emit(result, "building.modular.started", {
        version = "B0",
        pieceTypes = BuildPieceCatalog.Types(),
        maxPieces = validator.config.maxPieces,
    })

    return result
end

function ModularBuildingService.PreviewRoot(pieceType, requestedPosition, yawDegrees)
    local current = ModularBuildingService.Start()
    local definition = BuildPieceCatalog.Get(pieceType)
    if not definition then return { allowed = false, reason = "unknown_piece" } end

    local x, z = current.runtime.grid:WorldToCell(requestedPosition)
    if not x then return { allowed = false, reason = "outside_world" } end
    local terrainCenter = current.runtime.grid:CellCenter(x, z)
    local y = terrainCenter.Y + definition.size.Y * 0.5
    local cframe = current.validator:SnapRoot(Vector3.new(requestedPosition.X, y, requestedPosition.Z), yawDegrees)
    local allowed, reason = current.validator:ValidateRoot(pieceType, cframe)
    return {
        allowed = allowed,
        reason = reason,
        pieceType = pieceType,
        cframe = cframe,
        cost = definition.cost,
    }
end

function ModularBuildingService.PlaceRoot(pieceType, requestedPosition, yawDegrees, metadata)
    local current = ModularBuildingService.Start()
    local preview = ModularBuildingService.PreviewRoot(pieceType, requestedPosition, yawDegrees)
    if not preview.allowed then
        publishState(current, "place_root_failed", preview.reason, 0)
        return nil, preview.reason
    end

    local piece, reason = current.graph:PlaceRoot(pieceType, preview.cframe, metadata)
    if not piece then
        publishState(current, "place_root_failed", reason, 0)
        return nil, reason
    end
    renderPiece(current, piece)
    refreshStability(current)
    publishState(current, "place_root", "ok", 0)
    emit(current, "building.piece.placed", {
        pieceId = piece.id,
        pieceType = piece.pieceType,
        root = true,
        stability = piece.stability,
    })
    return piece, nil
end

function ModularBuildingService.PreviewSnap(pieceType, parentId, parentSocketName, attachmentName)
    local current = ModularBuildingService.Start()
    local allowed, reason, preview = current.validator:ValidateSnap(
        pieceType,
        parentId,
        parentSocketName,
        attachmentName
    )
    if not preview then
        preview = current.graph:PreviewSnap(pieceType, parentId, parentSocketName, attachmentName)
    end
    return {
        allowed = allowed,
        reason = reason,
        preview = preview,
    }
end

function ModularBuildingService.PlaceSnap(pieceType, parentId, parentSocketName, attachmentName, metadata)
    local current = ModularBuildingService.Start()
    local validation = ModularBuildingService.PreviewSnap(pieceType, parentId, parentSocketName, attachmentName)
    if not validation.allowed then
        publishState(current, "place_snap_failed", validation.reason, 0)
        return nil, validation.reason
    end

    local piece, reason = current.graph:PlaceSnap(pieceType, parentId, parentSocketName, attachmentName, metadata)
    if not piece then
        publishState(current, "place_snap_failed", reason, 0)
        return nil, reason
    end
    renderPiece(current, piece)
    refreshStability(current)
    publishState(current, "place_snap", "ok", 0)
    emit(current, "building.piece.placed", {
        pieceId = piece.id,
        pieceType = piece.pieceType,
        parentId = parentId,
        parentSocket = parentSocketName,
        stability = piece.stability,
    })
    return piece, nil
end

function ModularBuildingService.Remove(pieceId)
    local current = ModularBuildingService.Start()
    local removed, unstableOrReason = current.graph:Remove(pieceId)
    if not removed then
        publishState(current, "remove_failed", unstableOrReason, 0)
        return nil, unstableOrReason
    end

    destroyPieceInstance(pieceId)
    local collapsed = collapseUnstable(current, unstableOrReason)
    publishState(current, "remove", "ok", #collapsed)
    emit(current, "building.piece.removed", {
        pieceId = pieceId,
        collapsed = collapsed,
    })
    return {
        removed = removed,
        collapsed = collapsed,
    }, nil
end

function ModularBuildingService.GetOpenSockets(pieceId, kind)
    local current = ModularBuildingService.Start()
    return current.graph:GetOpenSockets(pieceId, kind)
end

function ModularBuildingService.GetPiece(pieceId)
    return ModularBuildingService.Start().graph:Get(pieceId)
end

function ModularBuildingService.GetGraph()
    return ModularBuildingService.Start().graph
end

function ModularBuildingService.GetResult()
    return result
end

return ModularBuildingService

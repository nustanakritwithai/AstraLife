local BuildPieceCatalog = require(script.Parent.BuildPieceCatalog)

local PlacementValidator = {}
PlacementValidator.__index = PlacementValidator

local DEFAULTS = {
    rootGrid = 2,
    rootYawStep = 90,
    maxPieces = 512,
    maxRootSlope = 0.35,
}

local function mergeConfig(config)
    local merged = {}
    for key, value in pairs(DEFAULTS) do
        merged[key] = config and config[key] ~= nil and config[key] or value
    end
    return merged
end

local function quantize(value, step)
    if step <= 0 then return value end
    return math.floor(value / step + 0.5) * step
end

function PlacementValidator.new(graph, config)
    assert(graph, "graph is required")
    config = config or {}
    return setmetatable({
        graph = graph,
        config = mergeConfig(config),
        environmentQuery = config.environmentQuery,
        collisionCheck = config.collisionCheck,
    }, PlacementValidator)
end

function PlacementValidator:SnapRoot(position, yawDegrees)
    local grid = self.config.rootGrid
    local yawStep = self.config.rootYawStep
    local snappedYaw = quantize(tonumber(yawDegrees) or 0, yawStep)
    local snappedPosition = Vector3.new(
        quantize(position.X, grid),
        position.Y,
        quantize(position.Z, grid)
    )
    return CFrame.new(snappedPosition) * CFrame.Angles(0, math.rad(snappedYaw), 0)
end

function PlacementValidator:_checkEnvironment(pieceType, cframe, rootPlacement)
    if not self.environmentQuery then
        return true, "ok"
    end

    local evaluation = self.environmentQuery:EvaluateActionAt(cframe.Position, "Build")
    if not evaluation.allowed then
        return false, evaluation.reason or "environment_blocked"
    end

    if rootPlacement then
        local cell = evaluation.cell
        if cell and (cell.slope or 0) >= self.config.maxRootSlope then
            return false, "root_slope_too_steep"
        end
    end
    return true, "ok"
end

function PlacementValidator:_checkCollision(pieceType, cframe, size, context)
    if not self.collisionCheck then return true, "ok" end
    local allowed, reason = self.collisionCheck(pieceType, cframe, size, context or {})
    if allowed == false then
        return false, reason or "collision_blocked"
    end
    return true, "ok"
end

function PlacementValidator:ValidateRoot(pieceType, cframe)
    local definition = BuildPieceCatalog.Get(pieceType)
    if not definition then return false, "unknown_piece" end
    if definition.grounded ~= true then return false, "root_requires_grounded_piece" end
    if self.graph:Count() >= self.config.maxPieces then return false, "piece_limit" end

    local environmentAllowed, environmentReason = self:_checkEnvironment(pieceType, cframe, true)
    if not environmentAllowed then return false, environmentReason end

    local collisionAllowed, collisionReason = self:_checkCollision(pieceType, cframe, definition.size, {
        rootPlacement = true,
    })
    if not collisionAllowed then return false, collisionReason end

    return true, "ok"
end

function PlacementValidator:ValidateSnap(pieceType, parentId, parentSocketName, attachmentName)
    if self.graph:Count() >= self.config.maxPieces then return false, "piece_limit" end

    local preview, reason = self.graph:PreviewSnap(pieceType, parentId, parentSocketName, attachmentName)
    if not preview then return false, reason end
    if preview.predictedStability < preview.minStability then
        return false, "insufficient_stability", preview
    end

    local definition = BuildPieceCatalog.Get(pieceType)
    if definition and definition.grounded then
        local environmentAllowed, environmentReason = self:_checkEnvironment(pieceType, preview.cframe, true)
        if not environmentAllowed then return false, environmentReason, preview end
    end

    local collisionAllowed, collisionReason = self:_checkCollision(pieceType, preview.cframe, preview.size, {
        rootPlacement = false,
        parentId = parentId,
        parentSocketName = parentSocketName,
        attachmentName = preview.attachmentName,
    })
    if not collisionAllowed then return false, collisionReason, preview end

    return true, "ok", preview
end

return PlacementValidator

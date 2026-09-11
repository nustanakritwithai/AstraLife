local BuildPieceCatalog = require(script.Parent.BuildPieceCatalog)
local BuildGraph = require(script.Parent.BuildGraph)
local PlacementValidator = require(script.Parent.PlacementValidator)

local B0Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function near(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 1e-4)
end

function B0Verifier.Run()
    local results = {}

    local types = BuildPieceCatalog.Types()
    check(#types >= 10, "pieceCatalog", results)
    check(
        BuildPieceCatalog.Has("FoundationSquare")
            and BuildPieceCatalog.Has("Wall")
            and BuildPieceCatalog.Has("DoorFrame")
            and BuildPieceCatalog.Has("FloorSquare")
            and BuildPieceCatalog.Has("Roof")
            and BuildPieceCatalog.Has("Stairs"),
        "corePieceSet",
        results
    )

    local graphA = BuildGraph.new()
    local validatorA = PlacementValidator.new(graphA)
    local rootCFrame = validatorA:SnapRoot(Vector3.new(0.4, 0, 0.6), 12)
    check(
        near(rootCFrame.Position.X, 0)
            and near(rootCFrame.Position.Z, 0),
        "rootGridSnap",
        results
    )

    local rootAllowed = validatorA:ValidateRoot("FoundationSquare", rootCFrame)
    local root = graphA:PlaceRoot("FoundationSquare", rootCFrame)
    check(rootAllowed and root ~= nil and root.stability == 1, "groundedFoundation", results)

    local preview = graphA:PreviewSnap("FoundationSquare", root.id, "FoundationSouth", "Edge")
    check(
        preview ~= nil
            and near(preview.cframe.Position.Z, 12)
            and preview.predictedStability == 1,
        "foundationSnapTransform",
        results
    )

    local adjacent = graphA:PlaceSnap("FoundationSquare", root.id, "FoundationSouth", "Edge")
    check(
        adjacent ~= nil
            and adjacent.parentId == root.id
            and adjacent.isGrounded
            and adjacent.stability == 1,
        "foundationExpansion",
        results
    )

    local duplicate, duplicateReason = graphA:PlaceSnap("FoundationSquare", root.id, "FoundationSouth", "Edge")
    check(duplicate == nil and duplicateReason == "socket_occupied", "socketOccupancy", results)

    local wall = graphA:PlaceSnap("Wall", root.id, "WallSouth", "Bottom")
    check(
        wall ~= nil
            and wall.stability > 0
            and wall.stability < root.stability,
        "wallSupportPropagation",
        results
    )

    local floor = graphA:PlaceSnap("FloorSquare", wall.id, "Top", "WallTop")
    check(
        floor ~= nil
            and near(floor.cframe.Position.Z, 0)
            and near(floor.cframe.Position.Y, 8.5)
            and floor.stability < wall.stability,
        "wallTopSnapFacesInward",
        results
    )

    local incompatible, incompatibleReason = graphA:PlaceSnap("Stairs", root.id, "WallWest", "Interior")
    check(incompatible == nil and incompatibleReason == "incompatible_socket", "socketCompatibility", results)

    local fingerprintA = graphA:Fingerprint()

    local graphB = BuildGraph.new()
    local rootB = graphB:PlaceRoot("FoundationSquare", rootCFrame)
    graphB:PlaceSnap("FoundationSquare", rootB.id, "FoundationSouth", "Edge")
    local wallB = graphB:PlaceSnap("Wall", rootB.id, "WallSouth", "Bottom")
    graphB:PlaceSnap("FloorSquare", wallB.id, "Top", "WallTop")
    local fingerprintB = graphB:Fingerprint()
    check(fingerprintA == fingerprintB, "deterministicFingerprint", results)

    local removed, unstable = graphA:Remove(root.id)
    local unstableSet = {}
    for _, id in ipairs(unstable or {}) do unstableSet[id] = true end
    check(
        removed ~= nil
            and graphA:Get(adjacent.id) ~= nil
            and graphA:Get(adjacent.id).stability == 1,
        "groundedExpansionSurvivesSupportRemoval",
        results
    )
    check(
        unstableSet[wall.id] == true
            and unstableSet[floor.id] == true
            and unstableSet[adjacent.id] ~= true,
        "supportRemovalInvalidatesUnsupportedChain",
        results
    )

    local environment = {
        EvaluateActionAt = function(_, position, action)
            if action == "Build" and position.X > 20 then
                return { allowed = false, reason = "unsafe_to_build", cell = { slope = 0.1 } }
            end
            return { allowed = true, reason = "ok", cell = { slope = position.Z > 20 and 0.6 or 0.1 } }
        end,
    }
    local environmentGraph = BuildGraph.new()
    local environmentValidator = PlacementValidator.new(environmentGraph, {
        environmentQuery = environment,
        collisionCheck = function(_, cframe)
            if cframe.Position.Z < -20 then return false, "collision_blocked" end
            return true, "ok"
        end,
    })

    local deniedEnvironment, deniedEnvironmentReason = environmentValidator:ValidateRoot(
        "FoundationSquare",
        CFrame.new(24, 0, 0)
    )
    check(not deniedEnvironment and deniedEnvironmentReason == "unsafe_to_build", "environmentGate", results)

    local deniedSlope, deniedSlopeReason = environmentValidator:ValidateRoot(
        "FoundationSquare",
        CFrame.new(0, 0, 24)
    )
    check(not deniedSlope and deniedSlopeReason == "root_slope_too_steep", "slopeGate", results)

    local deniedCollision, deniedCollisionReason = environmentValidator:ValidateRoot(
        "FoundationSquare",
        CFrame.new(0, 0, -24)
    )
    check(not deniedCollision and deniedCollisionReason == "collision_blocked", "collisionGate", results)

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results, {
        fingerprint = fingerprintB,
        pieceTypes = #types,
        samplePieceCount = graphB:Count(),
        unstableAfterRootRemoval = #(unstable or {}),
    }
end

return B0Verifier

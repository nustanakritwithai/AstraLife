local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local BuildingModules = Astra:WaitForChild("Building")
local MaterialGradeCatalog = require(BuildingModules.MaterialGradeCatalog)
local PieceLifecycle = require(BuildingModules.PieceLifecycle)
local PieceRenderer = require(BuildingModules.PieceRenderer)
local B1Verifier = require(BuildingModules.B1Verifier)

local ModularBuildingService = require(script.Parent.ModularBuildingService)

local BuildingLifecycleService = {}

local started = false
local result = nil

local function findInstance(renderFolder, pieceId)
    for _, child in ipairs(renderFolder:GetChildren()) do
        if child:GetAttribute("PieceId") == pieceId then return child end
    end
    return nil
end

local function refreshPiece(current, pieceId)
    local piece = current.graph:Get(pieceId)
    if not piece then return end
    current.lifecycle:EnsurePiece(piece)
    PieceRenderer.UpdateLifecycle(findInstance(current.renderFolder, pieceId), piece)
end

local function gradeCounts(current)
    local counts = {
        Scaffold = 0,
        Wood = 0,
        Stone = 0,
        Metal = 0,
    }
    local damaged = 0
    for _, piece in pairs(current.graph.pieces) do
        current.lifecycle:EnsurePiece(piece)
        counts[piece.materialGrade] = (counts[piece.materialGrade] or 0) + 1
        if piece.health < piece.maxHealth then damaged += 1 end
    end
    return counts, damaged
end

local function publishStats(current, action, reason)
    local state = current.state
    local stats = current.lifecycle:GetStats()
    local counts, damaged = gradeCounts(current)

    state:SetAttribute("Version", "B1")
    state:SetAttribute("B1Upgrades", stats.upgrades)
    state:SetAttribute("B1Repairs", stats.repairs)
    state:SetAttribute("B1DamageEvents", stats.damageEvents)
    state:SetAttribute("B1Destroyed", stats.destroyed)
    state:SetAttribute("B1Demolished", stats.demolished)
    state:SetAttribute("B1Duplicates", stats.duplicates)
    state:SetAttribute("B1Rejected", stats.rejected)
    state:SetAttribute("B1DamagedPieces", damaged)
    for grade, count in pairs(counts) do
        state:SetAttribute("B1Grade_" .. grade, count)
    end
    state:SetAttribute("B1LastAction", tostring(action or "none"))
    state:SetAttribute("B1LastReason", tostring(reason or "ok"))
end

local function emit(current, eventType, payload)
    local runtime = current.base.runtime
    if runtime and runtime.events then
        runtime.events:Emit(eventType, payload, runtime.clock.tick)
    end
end

function BuildingLifecycleService.Start()
    if started then return result end
    started = true

    local base = ModularBuildingService.Start()
    local lifecycle = PieceLifecycle.new(base.graph, { maxHistory = 2048 })
    lifecycle:EnsureAll()

    local passed, checks, verifierStats = B1Verifier.Run()
    base.state:SetAttribute("B1Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        base.state:SetAttribute("B1Check_" .. name, value)
    end
    base.state:SetAttribute("B1VerifierFinalGrade", verifierStats.finalGrade)
    base.state:SetAttribute("B1VerifierFinalHealth", verifierStats.finalHealth)
    base.state:SetAttribute("B1VerifierFinalMaxHealth", verifierStats.finalMaxHealth)
    base.state:SetAttribute("B1VerifierRefundedWood", verifierStats.refundedWood)

    result = {
        base = base,
        runtime = base.runtime,
        state = base.state,
        renderFolder = base.renderFolder,
        graph = base.graph,
        lifecycle = lifecycle,
        passed = passed,
        checks = checks,
    }
    publishStats(result, "start", "ok")

    emit(result, "building.lifecycle.started", {
        version = "B1",
        grades = MaterialGradeCatalog.Order(),
    })
    return result
end

function BuildingLifecycleService.GetPieceState(pieceId)
    local current = BuildingLifecycleService.Start()
    return current.lifecycle:Snapshot(pieceId)
end

function BuildingLifecycleService.GetGrades()
    return MaterialGradeCatalog.Order()
end

function BuildingLifecycleService.PreviewUpgrade(pieceId, targetGrade)
    local current = BuildingLifecycleService.Start()
    return current.lifecycle:PreviewUpgrade(pieceId, targetGrade)
end

function BuildingLifecycleService.Upgrade(pieceId, economy, transactionId, targetGrade)
    local current = BuildingLifecycleService.Start()
    local upgraded = current.lifecycle:Upgrade(pieceId, economy, transactionId, targetGrade)
    if upgraded.ok and not upgraded.duplicate then
        refreshPiece(current, pieceId)
        emit(current, "building.piece.upgraded", {
            pieceId = pieceId,
            fromGrade = upgraded.fromGrade,
            toGrade = upgraded.toGrade,
            health = upgraded.health,
            maxHealth = upgraded.maxHealth,
            transactionId = upgraded.transactionId,
        })
    end
    publishStats(current, "upgrade", upgraded.reason or "ok")
    return upgraded
end

function BuildingLifecycleService.ApplyDamage(pieceId, rawDamage, damageType, transactionId)
    local current = BuildingLifecycleService.Start()
    local damaged = current.lifecycle:ApplyDamage(pieceId, rawDamage, damageType, transactionId)
    local collapsed = {}

    if damaged.ok and not damaged.duplicate then
        if damaged.destroyed then
            local removal = ModularBuildingService.Remove(pieceId)
            if removal then collapsed = removal.collapsed or {} end
        else
            refreshPiece(current, pieceId)
        end
        emit(current, damaged.destroyed and "building.piece.destroyed" or "building.piece.damaged", {
            pieceId = pieceId,
            damageType = damaged.damageType,
            rawDamage = damaged.rawDamage,
            appliedDamage = damaged.appliedDamage,
            health = damaged.health,
            maxHealth = damaged.maxHealth,
            collapsed = collapsed,
            transactionId = damaged.transactionId,
        })
    end

    damaged.collapsed = collapsed
    publishStats(current, "damage", damaged.reason or "ok")
    return damaged
end

function BuildingLifecycleService.PreviewRepair(pieceId, requestedHealth)
    local current = BuildingLifecycleService.Start()
    return current.lifecycle:PreviewRepair(pieceId, requestedHealth)
end

function BuildingLifecycleService.Repair(pieceId, economy, requestedHealth, transactionId)
    local current = BuildingLifecycleService.Start()
    local repaired = current.lifecycle:Repair(pieceId, economy, requestedHealth, transactionId)
    if repaired.ok and not repaired.duplicate then
        refreshPiece(current, pieceId)
        emit(current, "building.piece.repaired", {
            pieceId = pieceId,
            repairedHealth = repaired.repairedHealth,
            health = repaired.health,
            maxHealth = repaired.maxHealth,
            transactionId = repaired.transactionId,
        })
    end
    publishStats(current, "repair", repaired.reason or "ok")
    return repaired
end

function BuildingLifecycleService.PreviewDemolish(pieceId)
    local current = BuildingLifecycleService.Start()
    return current.lifecycle:PreviewDemolish(pieceId)
end

function BuildingLifecycleService.Demolish(pieceId, economy, transactionId)
    local current = BuildingLifecycleService.Start()
    local function removeCallback(id)
        local piece = current.graph:Get(id)
        if not piece then return nil, "missing_piece" end
        local removal, reason = ModularBuildingService.Remove(id)
        if not removal then return nil, reason end
        return piece, removal.collapsed or {}
    end

    local demolished = current.lifecycle:Demolish(
        pieceId,
        economy,
        transactionId,
        removeCallback
    )
    if demolished.ok and not demolished.duplicate then
        emit(current, "building.piece.demolished", {
            pieceId = pieceId,
            grade = demolished.grade,
            refund = demolished.refund,
            refunded = demolished.refunded,
            collapsed = demolished.unstable,
            transactionId = demolished.transactionId,
        })
    end
    publishStats(current, "demolish", demolished.reason or "ok")
    return demolished
end

function BuildingLifecycleService.GetResult()
    return result
end

return BuildingLifecycleService

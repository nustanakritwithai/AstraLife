local MaterialGradeCatalog = require(script.Parent.MaterialGradeCatalog)

local PieceLifecycle = {}
PieceLifecycle.__index = PieceLifecycle

local function cloneTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = type(value) == "table" and cloneTable(value) or value
    end
    return result
end

local function recipeHasCost(recipe)
    for _, amount in pairs(recipe or {}) do
        if (tonumber(amount) or 0) > 0 then return true end
    end
    return false
end

local function canAfford(economy, recipe)
    if not recipeHasCost(recipe) then return true, "ok" end
    if not economy then return false, "economy_required" end
    if type(economy.CanAfford) == "function" and economy:CanAfford(recipe) ~= true then
        return false, "insufficient_resources"
    end
    if type(economy.Spend) ~= "function" then return false, "economy_missing_spend" end
    return true, "ok"
end

local function spend(economy, recipe)
    if not recipeHasCost(recipe) then return true end
    return economy and type(economy.Spend) == "function" and economy:Spend(recipe) == true
end

local function canDeposit(economy, recipe)
    if not recipeHasCost(recipe) then return true, "ok" end
    if not economy then return true, "no_receiver" end
    if type(economy.CanDeposit) == "function" and economy:CanDeposit(recipe) ~= true then
        return false, "refund_capacity"
    end
    if type(economy.Deposit) ~= "function" then return false, "economy_missing_deposit" end
    return true, "ok"
end

local function deposit(economy, recipe)
    if not recipeHasCost(recipe) then return true end
    if not economy then return true end
    return type(economy.Deposit) == "function" and economy:Deposit(recipe) == true
end

local function scope(action, pieceId, qualifier)
    return table.concat({ tostring(action), tostring(pieceId), tostring(qualifier or "") }, "|")
end

function PieceLifecycle.new(graph, config)
    assert(graph, "graph is required")
    config = config or {}
    return setmetatable({
        graph = graph,
        maxHistory = math.max(32, math.floor(config.maxHistory or 2048)),
        sequence = 0,
        seen = {},
        order = {},
        pendingRefunds = {},
        stats = {
            upgrades = 0,
            repairs = 0,
            damageEvents = 0,
            destroyed = 0,
            demolished = 0,
            duplicates = 0,
            conflicts = 0,
            refundPending = 0,
            refundRetries = 0,
            rejected = 0,
        },
    }, PieceLifecycle)
end

function PieceLifecycle:_nextId(prefix)
    self.sequence += 1
    return string.format("%s:%d", prefix or "building", self.sequence)
end

function PieceLifecycle:_conflict(transactionId, action, pieceId)
    self.stats.conflicts += 1
    self.stats.rejected += 1
    return {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = action,
        pieceId = pieceId,
        reason = "transaction_conflict",
    }
end

function PieceLifecycle:_remember(transactionId, transactionScope, result)
    self.seen[transactionId] = {
        scope = transactionScope,
        result = cloneTable(result),
    }
    table.insert(self.order, transactionId)
    while #self.order > self.maxHistory do
        local expired = table.remove(self.order, 1)
        self.seen[expired] = nil
    end
end

function PieceLifecycle:_dedupe(transactionId, transactionScope, action, pieceId)
    local previous = self.seen[transactionId]
    if not previous then return nil end
    if previous.scope ~= transactionScope then
        return self:_conflict(transactionId, action, pieceId)
    end
    self.stats.duplicates += 1
    local copy = cloneTable(previous.result)
    copy.duplicate = true
    return copy
end

function PieceLifecycle:_resumePendingRefund(transactionId, transactionScope, economy, action, pieceId)
    local pending = self.pendingRefunds[transactionId]
    if not pending then return nil end
    if pending.scope ~= transactionScope then
        return self:_conflict(transactionId, action, pieceId)
    end

    self.stats.refundRetries += 1
    local result = cloneTable(pending.result)
    result.resumed = true
    if deposit(economy, result.refund) then
        result.ok = true
        result.reason = nil
        result.refunded = true
        self.pendingRefunds[transactionId] = nil
        self:_remember(transactionId, transactionScope, result)
    else
        result.ok = false
        result.reason = "refund_pending"
        result.refunded = false
    end
    return cloneTable(result)
end

function PieceLifecycle:EnsurePiece(piece)
    if not piece then return nil end

    local grade = piece.materialGrade
    if not MaterialGradeCatalog.IsValid(grade) then
        grade = MaterialGradeCatalog.DefaultGrade()
        piece.materialGrade = grade
    end

    local expectedMax = MaterialGradeCatalog.MaxHealth(piece.pieceType, grade) or 1
    if piece.maxHealth == nil or piece.maxHealth <= 0 then piece.maxHealth = expectedMax end
    if piece.health == nil then piece.health = piece.maxHealth end

    piece.maxHealth = math.max(1, piece.maxHealth)
    piece.health = math.clamp(piece.health, 0, piece.maxHealth)
    piece.destroyed = piece.destroyed == true or piece.health <= 0
    return piece
end

function PieceLifecycle:EnsureAll()
    for _, piece in pairs(self.graph.pieces) do self:EnsurePiece(piece) end
end

function PieceLifecycle:Snapshot(pieceId)
    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    if not piece then return nil end
    return {
        pieceId = piece.id,
        pieceType = piece.pieceType,
        grade = piece.materialGrade,
        health = piece.health,
        maxHealth = piece.maxHealth,
        healthRatio = piece.maxHealth > 0 and piece.health / piece.maxHealth or 0,
        destroyed = piece.destroyed == true,
    }
end

function PieceLifecycle:PreviewUpgrade(pieceId, targetGrade)
    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    if not piece then return nil, "missing_piece" end
    if piece.destroyed then return nil, "piece_destroyed" end

    local recipe, reason, nextGrade = MaterialGradeCatalog.UpgradeRecipe(
        piece.pieceType,
        piece.materialGrade,
        targetGrade
    )
    if not recipe then return nil, reason end

    return {
        pieceId = piece.id,
        fromGrade = piece.materialGrade,
        toGrade = nextGrade,
        recipe = recipe,
        currentHealth = piece.health,
        currentMaxHealth = piece.maxHealth,
        nextMaxHealth = MaterialGradeCatalog.MaxHealth(piece.pieceType, nextGrade),
        healthRatio = piece.maxHealth > 0 and piece.health / piece.maxHealth or 0,
    }, nil
end

function PieceLifecycle:Upgrade(pieceId, economy, transactionId, targetGrade)
    transactionId = tostring(transactionId or self:_nextId("upgrade"))
    local transactionScope = scope("Upgrade", pieceId, targetGrade or "next")
    local previous = self:_dedupe(transactionId, transactionScope, "Upgrade", pieceId)
    if previous then return previous end

    local preview, reason = self:PreviewUpgrade(pieceId, targetGrade)
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Upgrade",
        pieceId = pieceId,
        reason = reason,
    }
    if not preview then
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    local affordable, affordabilityReason = canAfford(economy, preview.recipe)
    if not affordable or not spend(economy, preview.recipe) then
        result.reason = not affordable and affordabilityReason or "spend_failed"
        result.recipe = cloneTable(preview.recipe)
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    piece.materialGrade = preview.toGrade
    piece.maxHealth = preview.nextMaxHealth
    piece.health = math.clamp(piece.maxHealth * preview.healthRatio, 0, piece.maxHealth)
    piece.destroyed = piece.health <= 0

    result.ok = true
    result.reason = nil
    result.fromGrade = preview.fromGrade
    result.toGrade = preview.toGrade
    result.recipe = cloneTable(preview.recipe)
    result.health = piece.health
    result.maxHealth = piece.maxHealth
    self.stats.upgrades += 1
    self:_remember(transactionId, transactionScope, result)
    return cloneTable(result)
end

function PieceLifecycle:ApplyDamage(pieceId, rawDamage, damageType, transactionId)
    local normalizedDamage = math.max(0, tonumber(rawDamage) or 0)
    local normalizedType = damageType or "Generic"
    transactionId = tostring(transactionId or self:_nextId("damage"))
    local qualifier = string.format("%.6f|%s", normalizedDamage, tostring(normalizedType))
    local transactionScope = scope("Damage", pieceId, qualifier)
    local previous = self:_dedupe(transactionId, transactionScope, "Damage", pieceId)
    if previous then return previous end

    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Damage",
        pieceId = pieceId,
        damageType = normalizedType,
        rawDamage = normalizedDamage,
    }

    if not piece then
        result.reason = "missing_piece"
    elseif piece.destroyed then
        result.reason = "piece_destroyed"
    elseif normalizedDamage <= 0 then
        result.reason = "invalid_damage"
    else
        local multiplier = MaterialGradeCatalog.DamageMultiplier(piece.materialGrade, normalizedType)
        local applied = math.min(piece.health, normalizedDamage * multiplier)
        piece.health = math.max(0, piece.health - applied)
        piece.destroyed = piece.health <= 0
        result.ok = true
        result.grade = piece.materialGrade
        result.multiplier = multiplier
        result.appliedDamage = applied
        result.health = piece.health
        result.maxHealth = piece.maxHealth
        result.destroyed = piece.destroyed
        self.stats.damageEvents += 1
        if piece.destroyed then self.stats.destroyed += 1 end
    end

    if not result.ok then self.stats.rejected += 1 end
    self:_remember(transactionId, transactionScope, result)
    return cloneTable(result)
end

function PieceLifecycle:PreviewRepair(pieceId, requestedHealth)
    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    if not piece then return nil, "missing_piece" end
    if piece.destroyed then return nil, "piece_destroyed" end

    local missing = math.max(0, piece.maxHealth - piece.health)
    if missing <= 1e-6 then return nil, "full_health" end

    local repairHealth = math.min(missing, math.max(0, tonumber(requestedHealth) or missing))
    if repairHealth <= 0 then return nil, "invalid_repair_amount" end

    return {
        pieceId = piece.id,
        grade = piece.materialGrade,
        repairHealth = repairHealth,
        missingHealth = missing,
        recipe = MaterialGradeCatalog.RepairRecipe(
            piece.pieceType,
            piece.materialGrade,
            repairHealth / piece.maxHealth
        ),
        currentHealth = piece.health,
        maxHealth = piece.maxHealth,
    }, nil
end

function PieceLifecycle:Repair(pieceId, economy, requestedHealth, transactionId)
    local qualifier = requestedHealth == nil and "missing" or string.format("%.6f", tonumber(requestedHealth) or 0)
    transactionId = tostring(transactionId or self:_nextId("repair"))
    local transactionScope = scope("Repair", pieceId, qualifier)
    local previous = self:_dedupe(transactionId, transactionScope, "Repair", pieceId)
    if previous then return previous end

    local preview, reason = self:PreviewRepair(pieceId, requestedHealth)
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Repair",
        pieceId = pieceId,
        reason = reason,
    }
    if not preview then
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    local affordable, affordabilityReason = canAfford(economy, preview.recipe)
    if not affordable or not spend(economy, preview.recipe) then
        result.reason = not affordable and affordabilityReason or "spend_failed"
        result.recipe = cloneTable(preview.recipe)
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    piece.health = math.min(piece.maxHealth, piece.health + preview.repairHealth)
    result.ok = true
    result.reason = nil
    result.grade = piece.materialGrade
    result.repairedHealth = preview.repairHealth
    result.recipe = cloneTable(preview.recipe)
    result.health = piece.health
    result.maxHealth = piece.maxHealth
    self.stats.repairs += 1
    self:_remember(transactionId, transactionScope, result)
    return cloneTable(result)
end

function PieceLifecycle:PreviewDemolish(pieceId)
    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    if not piece then return nil, "missing_piece" end
    return {
        pieceId = piece.id,
        pieceType = piece.pieceType,
        grade = piece.materialGrade,
        refund = MaterialGradeCatalog.DemolishRefund(piece.pieceType, piece.materialGrade),
    }, nil
end

function PieceLifecycle:Demolish(pieceId, economy, transactionId, removeCallback)
    transactionId = tostring(transactionId or self:_nextId("demolish"))
    local transactionScope = scope("Demolish", pieceId)

    local resumed = self:_resumePendingRefund(
        transactionId,
        transactionScope,
        economy,
        "Demolish",
        pieceId
    )
    if resumed then return resumed end

    local previous = self:_dedupe(transactionId, transactionScope, "Demolish", pieceId)
    if previous then return previous end

    local preview, reason = self:PreviewDemolish(pieceId)
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Demolish",
        pieceId = pieceId,
        reason = reason,
    }
    if not preview then
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end
    if type(removeCallback) ~= "function" then
        result.reason = "remove_callback_required"
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    local canRefund, refundReason = canDeposit(economy, preview.refund)
    if not canRefund then
        result.reason = refundReason
        result.refund = cloneTable(preview.refund)
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    local removed, unstableOrReason = removeCallback(pieceId)
    if not removed then
        result.reason = unstableOrReason or "remove_failed"
        self.stats.rejected += 1
        self:_remember(transactionId, transactionScope, result)
        return cloneTable(result)
    end

    result.grade = preview.grade
    result.refund = cloneTable(preview.refund)
    result.unstable = cloneTable(unstableOrReason or {})
    result.removed = true
    self.stats.demolished += 1

    if deposit(economy, preview.refund) then
        result.ok = true
        result.refunded = true
        self:_remember(transactionId, transactionScope, result)
    else
        result.ok = false
        result.reason = "refund_pending"
        result.refunded = false
        self.pendingRefunds[transactionId] = {
            scope = transactionScope,
            result = cloneTable(result),
        }
        self.stats.refundPending += 1
    end

    return cloneTable(result)
end

function PieceLifecycle:GetStats()
    local pending = 0
    for _ in pairs(self.pendingRefunds) do pending += 1 end
    local result = {
        sequence = self.sequence,
        remembered = #self.order,
        pendingRefunds = pending,
    }
    for key, value in pairs(self.stats) do result[key] = value end
    return result
end

return PieceLifecycle

local MaterialGradeCatalog = require(script.Parent.MaterialGradeCatalog)

local PieceLifecycle = {}
PieceLifecycle.__index = PieceLifecycle

local function cloneTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = cloneTable(value)
        else
            result[key] = value
        end
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
    if type(economy.CanAfford) == "function" then
        if economy:CanAfford(recipe) ~= true then return false, "insufficient_resources" end
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

function PieceLifecycle.new(graph, config)
    assert(graph, "graph is required")
    config = config or {}
    return setmetatable({
        graph = graph,
        maxHistory = math.max(32, math.floor(config.maxHistory or 2048)),
        sequence = 0,
        seen = {},
        order = {},
        stats = {
            upgrades = 0,
            repairs = 0,
            damageEvents = 0,
            destroyed = 0,
            demolished = 0,
            duplicates = 0,
            rejected = 0,
        },
    }, PieceLifecycle)
end

function PieceLifecycle:_nextId(prefix)
    self.sequence += 1
    return string.format("%s:%d", prefix or "building", self.sequence)
end

function PieceLifecycle:_remember(transactionId, result)
    self.seen[transactionId] = cloneTable(result)
    table.insert(self.order, transactionId)
    while #self.order > self.maxHistory do
        local expired = table.remove(self.order, 1)
        self.seen[expired] = nil
    end
end

function PieceLifecycle:_dedupe(transactionId)
    local previous = self.seen[transactionId]
    if not previous then return nil end
    self.stats.duplicates += 1
    local copy = cloneTable(previous)
    copy.duplicate = true
    return copy
end

function PieceLifecycle:EnsurePiece(piece)
    if not piece then return nil end

    local grade = piece.materialGrade
    if not MaterialGradeCatalog.IsValid(grade) then
        grade = MaterialGradeCatalog.DefaultGrade()
        piece.materialGrade = grade
    end

    local expectedMax = MaterialGradeCatalog.MaxHealth(piece.pieceType, grade) or 1
    if piece.maxHealth == nil or piece.maxHealth <= 0 then
        piece.maxHealth = expectedMax
    end
    if piece.health == nil then
        piece.health = piece.maxHealth
    end

    piece.maxHealth = math.max(1, piece.maxHealth)
    piece.health = math.clamp(piece.health, 0, piece.maxHealth)
    piece.destroyed = piece.destroyed == true or piece.health <= 0
    return piece
end

function PieceLifecycle:EnsureAll()
    for _, piece in pairs(self.graph.pieces) do
        self:EnsurePiece(piece)
    end
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

    local nextMax = MaterialGradeCatalog.MaxHealth(piece.pieceType, nextGrade)
    return {
        pieceId = piece.id,
        fromGrade = piece.materialGrade,
        toGrade = nextGrade,
        recipe = recipe,
        currentHealth = piece.health,
        currentMaxHealth = piece.maxHealth,
        nextMaxHealth = nextMax,
        healthRatio = piece.maxHealth > 0 and piece.health / piece.maxHealth or 0,
    }, nil
end

function PieceLifecycle:Upgrade(pieceId, economy, transactionId, targetGrade)
    transactionId = tostring(transactionId or self:_nextId("upgrade"))
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

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
        self:_remember(transactionId, result)
        return cloneTable(result)
    end

    local affordable, affordabilityReason = canAfford(economy, preview.recipe)
    if not affordable then
        result.reason = affordabilityReason
        result.recipe = cloneTable(preview.recipe)
        self.stats.rejected += 1
        self:_remember(transactionId, result)
        return cloneTable(result)
    end
    if not spend(economy, preview.recipe) then
        result.reason = "spend_failed"
        result.recipe = cloneTable(preview.recipe)
        self.stats.rejected += 1
        self:_remember(transactionId, result)
        return cloneTable(result)
    end

    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    local ratio = preview.healthRatio
    piece.materialGrade = preview.toGrade
    piece.maxHealth = preview.nextMaxHealth
    piece.health = math.clamp(piece.maxHealth * ratio, 0, piece.maxHealth)
    piece.destroyed = piece.health <= 0

    result.ok = true
    result.reason = nil
    result.fromGrade = preview.fromGrade
    result.toGrade = preview.toGrade
    result.recipe = cloneTable(preview.recipe)
    result.health = piece.health
    result.maxHealth = piece.maxHealth
    self.stats.upgrades += 1
    self:_remember(transactionId, result)
    return cloneTable(result)
end

function PieceLifecycle:ApplyDamage(pieceId, rawDamage, damageType, transactionId)
    transactionId = tostring(transactionId or self:_nextId("damage"))
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    local result = {
        ok = false,
        duplicate = false,
        transactionId = transactionId,
        action = "Damage",
        pieceId = pieceId,
        damageType = damageType or "Generic",
        rawDamage = math.max(0, tonumber(rawDamage) or 0),
    }

    if not piece then
        result.reason = "missing_piece"
    elseif piece.destroyed then
        result.reason = "piece_destroyed"
    elseif result.rawDamage <= 0 then
        result.reason = "invalid_damage"
    else
        local multiplier = MaterialGradeCatalog.DamageMultiplier(piece.materialGrade, result.damageType)
        local applied = math.min(piece.health, result.rawDamage * multiplier)
        piece.health = math.max(0, piece.health - applied)
        piece.destroyed = piece.health <= 0

        result.ok = true
        result.reason = nil
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
    self:_remember(transactionId, result)
    return cloneTable(result)
end

function PieceLifecycle:PreviewRepair(pieceId, requestedHealth)
    local piece = self:EnsurePiece(self.graph:Get(pieceId))
    if not piece then return nil, "missing_piece" end
    if piece.destroyed then return nil, "piece_destroyed" end

    local missing = math.max(0, piece.maxHealth - piece.health)
    if missing <= 1e-6 then return nil, "full_health" end

    local repairHealth = math.min(
        missing,
        math.max(0, tonumber(requestedHealth) or missing)
    )
    if repairHealth <= 0 then return nil, "invalid_repair_amount" end

    local ratio = repairHealth / piece.maxHealth
    local recipe = MaterialGradeCatalog.RepairRecipe(piece.pieceType, piece.materialGrade, ratio)
    return {
        pieceId = piece.id,
        grade = piece.materialGrade,
        repairHealth = repairHealth,
        missingHealth = missing,
        recipe = recipe,
        currentHealth = piece.health,
        maxHealth = piece.maxHealth,
    }, nil
end

function PieceLifecycle:Repair(pieceId, economy, requestedHealth, transactionId)
    transactionId = tostring(transactionId or self:_nextId("repair"))
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

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
        self:_remember(transactionId, result)
        return cloneTable(result)
    end

    local affordable, affordabilityReason = canAfford(economy, preview.recipe)
    if not affordable then
        result.reason = affordabilityReason
        result.recipe = cloneTable(preview.recipe)
        self.stats.rejected += 1
        self:_remember(transactionId, result)
        return cloneTable(result)
    end
    if not spend(economy, preview.recipe) then
        result.reason = "spend_failed"
        result.recipe = cloneTable(preview.recipe)
        self.stats.rejected += 1
        self:_remember(transactionId, result)
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
    self:_remember(transactionId, result)
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
    local duplicate = self:_dedupe(transactionId)
    if duplicate then return duplicate end

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
        self:_remember(transactionId, result)
        return cloneTable(result)
    end
    if type(removeCallback) ~= "function" then
        result.reason = "remove_callback_required"
        self.stats.rejected += 1
        self:_remember(transactionId, result)
        return cloneTable(result)
    end

    local canRefund, refundReason = canDeposit(economy, preview.refund)
    if not canRefund then
        result.reason = refundReason
        result.refund = cloneTable(preview.refund)
        self.stats.rejected += 1
        self:_remember(transactionId, result)
        return cloneTable(result)
    end

    local removed, unstableOrReason = removeCallback(pieceId)
    if not removed then
        result.reason = unstableOrReason or "remove_failed"
        self.stats.rejected += 1
        self:_remember(transactionId, result)
        return cloneTable(result)
    end

    local refunded = deposit(economy, preview.refund)
    result.ok = true
    result.reason = refunded and nil or "refund_pending"
    result.grade = preview.grade
    result.refund = cloneTable(preview.refund)
    result.refunded = refunded
    result.unstable = cloneTable(unstableOrReason or {})
    self.stats.demolished += 1
    self:_remember(transactionId, result)
    return cloneTable(result)
end

function PieceLifecycle:GetStats()
    local result = {
        sequence = self.sequence,
        remembered = #self.order,
    }
    for key, value in pairs(self.stats) do result[key] = value end
    return result
end

return PieceLifecycle

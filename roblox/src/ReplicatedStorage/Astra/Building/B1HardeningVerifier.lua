local BuildGraph = require(script.Parent.BuildGraph)
local PieceLifecycle = require(script.Parent.PieceLifecycle)

local B1HardeningVerifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function makeEconomy(initial, failDeposits)
    local wallet = {
        stock = {},
        spent = {},
        deposited = {},
        depositAttempts = 0,
        failDeposits = failDeposits or 0,
    }
    for key, value in pairs(initial or {}) do wallet.stock[key] = value end

    function wallet:CanAfford(recipe)
        for resourceType, amount in pairs(recipe or {}) do
            if (self.stock[resourceType] or 0) + 1e-9 < amount then return false end
        end
        return true
    end

    function wallet:Spend(recipe)
        if not self:CanAfford(recipe) then return false end
        for resourceType, amount in pairs(recipe or {}) do
            self.stock[resourceType] = (self.stock[resourceType] or 0) - amount
            self.spent[resourceType] = (self.spent[resourceType] or 0) + amount
        end
        return true
    end

    function wallet:CanDeposit()
        return true
    end

    function wallet:Deposit(recipe)
        self.depositAttempts += 1
        if self.depositAttempts <= self.failDeposits then return false end
        for resourceType, amount in pairs(recipe or {}) do
            self.stock[resourceType] = (self.stock[resourceType] or 0) + amount
            self.deposited[resourceType] = (self.deposited[resourceType] or 0) + amount
        end
        return true
    end

    return wallet
end

function B1HardeningVerifier.Run()
    local results = {}

    local graph = BuildGraph.new()
    local lifecycle = PieceLifecycle.new(graph, { maxHistory = 64 })
    local piece = graph:PlaceRoot("FoundationSquare", CFrame.new())
    lifecycle:EnsurePiece(piece)

    local healthBefore = piece.health
    local firstDamage = lifecycle:ApplyDamage(piece.id, 10, "Generic", "hardening:damage")
    local healthAfterFirst = piece.health
    local duplicateDamage = lifecycle:ApplyDamage(piece.id, 10, "Generic", "hardening:damage")
    check(
        firstDamage.ok
            and duplicateDamage.ok
            and duplicateDamage.duplicate
            and piece.health == healthAfterFirst
            and healthAfterFirst < healthBefore,
        "sameDamageRetryIdempotent",
        results
    )

    local conflictDamage = lifecycle:ApplyDamage(piece.id, 20, "Generic", "hardening:damage")
    check(
        not conflictDamage.ok
            and conflictDamage.reason == "transaction_conflict"
            and piece.health == healthAfterFirst,
        "changedDamageWithSameIdRejected",
        results
    )

    local economy = makeEconomy({ Stone = 1000, Wood = 1000 })
    local crossAction = lifecycle:Upgrade(piece.id, economy, "hardening:damage")
    check(
        not crossAction.ok
            and crossAction.reason == "transaction_conflict"
            and piece.materialGrade == "Wood",
        "crossActionTransactionConflict",
        results
    )

    local refundGraph = BuildGraph.new()
    local refundLifecycle = PieceLifecycle.new(refundGraph, { maxHistory = 64 })
    local refundPiece = refundGraph:PlaceRoot("FoundationSquare", CFrame.new())
    refundLifecycle:EnsurePiece(refundPiece)
    local flaky = makeEconomy({}, 1)
    local removedCalls = 0
    local function removeCallback(pieceId)
        removedCalls += 1
        return refundGraph:Remove(pieceId)
    end

    local firstDemolish = refundLifecycle:Demolish(
        refundPiece.id,
        flaky,
        "hardening:refund",
        removeCallback
    )
    check(
        not firstDemolish.ok
            and firstDemolish.reason == "refund_pending"
            and firstDemolish.removed == true
            and firstDemolish.refunded == false
            and refundGraph:Get(refundPiece.id) == nil
            and removedCalls == 1
            and flaky.depositAttempts == 1,
        "failedRefundBecomesPending",
        results
    )

    local resumed = refundLifecycle:Demolish(
        refundPiece.id,
        flaky,
        "hardening:refund",
        removeCallback
    )
    local depositedWood = flaky.deposited.Wood or 0
    check(
        resumed.ok
            and resumed.refunded
            and resumed.resumed
            and removedCalls == 1
            and flaky.depositAttempts == 2
            and depositedWood > 0,
        "pendingRefundRetryRecovers",
        results
    )

    local duplicateDemolish = refundLifecycle:Demolish(
        refundPiece.id,
        flaky,
        "hardening:refund",
        removeCallback
    )
    check(
        duplicateDemolish.ok
            and duplicateDemolish.duplicate
            and removedCalls == 1
            and flaky.depositAttempts == 2
            and (flaky.deposited.Wood or 0) == depositedWood,
        "completedRefundRetryNoDuplicate",
        results
    )

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    local stats = refundLifecycle:GetStats()
    return passed, results, {
        removedCalls = removedCalls,
        depositAttempts = flaky.depositAttempts,
        depositedWood = depositedWood,
        pendingRefunds = stats.pendingRefunds,
    }
end

return B1HardeningVerifier

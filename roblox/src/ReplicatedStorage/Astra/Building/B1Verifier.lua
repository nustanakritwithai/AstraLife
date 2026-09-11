local BuildGraph = require(script.Parent.BuildGraph)
local MaterialGradeCatalog = require(script.Parent.MaterialGradeCatalog)
local PieceLifecycle = require(script.Parent.PieceLifecycle)

local B1Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function near(a, b, epsilon)
    return math.abs((a or 0) - (b or 0)) <= (epsilon or 1e-6)
end

local function makeEconomy(initial)
    local wallet = {
        stock = {},
        spent = {},
        deposited = {},
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
        for resourceType, amount in pairs(recipe or {}) do
            self.stock[resourceType] = (self.stock[resourceType] or 0) + amount
            self.deposited[resourceType] = (self.deposited[resourceType] or 0) + amount
        end
        return true
    end

    return wallet
end

function B1Verifier.Run()
    local results = {}

    local order = MaterialGradeCatalog.Order()
    check(
        #order == 4
            and order[1] == "Scaffold"
            and order[2] == "Wood"
            and order[3] == "Stone"
            and order[4] == "Metal",
        "gradeOrder",
        results
    )
    check(
        MaterialGradeCatalog.Next("Wood") == "Stone"
            and MaterialGradeCatalog.Next("Stone") == "Metal"
            and MaterialGradeCatalog.Next("Metal") == nil,
        "upgradeSequence",
        results
    )

    local graph = BuildGraph.new()
    local lifecycle = PieceLifecycle.new(graph, { maxHistory = 64 })
    local piece = graph:PlaceRoot("FoundationSquare", CFrame.new())
    lifecycle:EnsurePiece(piece)

    check(
        piece.materialGrade == "Wood"
            and piece.health == piece.maxHealth
            and piece.maxHealth == MaterialGradeCatalog.MaxHealth("FoundationSquare", "Wood"),
        "defaultWoodLifecycle",
        results
    )

    local woodMax = piece.maxHealth
    local damage = lifecycle:ApplyDamage(piece.id, 250, "Generic", "verify:damage")
    local ratioBeforeUpgrade = piece.health / piece.maxHealth
    check(
        damage.ok
            and piece.health < woodMax
            and piece.health >= 0,
        "damageReducesHealth",
        results
    )

    local insufficient = makeEconomy({ Stone = 0 })
    local denied = lifecycle:Upgrade(piece.id, insufficient, "verify:denied-upgrade")
    check(
        not denied.ok
            and denied.reason == "insufficient_resources"
            and piece.materialGrade == "Wood",
        "upgradeRequiresResources",
        results
    )

    local upgradePreview = lifecycle:PreviewUpgrade(piece.id)
    local stoneCost = upgradePreview and upgradePreview.recipe.Stone or 0
    local economy = makeEconomy({ Stone = stoneCost + 10, Metal = 1000, Wood = 1000 })
    local stoneBefore = economy.stock.Stone
    local upgraded = lifecycle:Upgrade(piece.id, economy, "verify:upgrade-stone")
    local stoneAfter = economy.stock.Stone
    local ratioAfterUpgrade = piece.health / piece.maxHealth
    check(
        upgraded.ok
            and upgraded.toGrade == "Stone"
            and piece.materialGrade == "Stone"
            and near(stoneBefore - stoneAfter, stoneCost)
            and near(ratioBeforeUpgrade, ratioAfterUpgrade, 1e-6),
        "upgradePreservesHealthRatio",
        results
    )

    local duplicateUpgrade = lifecycle:Upgrade(piece.id, economy, "verify:upgrade-stone")
    check(
        duplicateUpgrade.ok
            and duplicateUpgrade.duplicate
            and near(economy.stock.Stone, stoneAfter),
        "upgradeIdempotent",
        results
    )

    local skipUpgrade = lifecycle:Upgrade(piece.id, economy, "verify:skip-grade", "Metal")
    check(
        skipUpgrade.ok and piece.materialGrade == "Metal",
        "nextGradeUpgradeAllowed",
        results
    )
    local noHigher = lifecycle:Upgrade(piece.id, economy, "verify:max-grade")
    check(
        not noHigher.ok and noHigher.reason == "max_grade",
        "maxGradeStopsUpgrade",
        results
    )

    local repairDamage = lifecycle:ApplyDamage(piece.id, 400, "Explosion", "verify:repair-damage")
    local healthBeforeRepair = piece.health
    local repairPreview = lifecycle:PreviewRepair(piece.id, piece.maxHealth * 0.20)
    local metalBeforeRepair = economy.stock.Metal
    local repair = lifecycle:Repair(piece.id, economy, piece.maxHealth * 0.20, "verify:repair")
    check(
        repairDamage.ok
            and repairPreview ~= nil
            and repair.ok
            and piece.health > healthBeforeRepair
            and piece.health <= piece.maxHealth
            and economy.stock.Metal < metalBeforeRepair,
        "repairCostsAndRestoresHealth",
        results
    )
    local metalAfterRepair = economy.stock.Metal
    local duplicateRepair = lifecycle:Repair(piece.id, economy, piece.maxHealth, "verify:repair")
    check(
        duplicateRepair.ok
            and duplicateRepair.duplicate
            and near(economy.stock.Metal, metalAfterRepair),
        "repairIdempotent",
        results
    )

    local woodGraph = BuildGraph.new()
    local woodLifecycle = PieceLifecycle.new(woodGraph, { maxHistory = 32 })
    local woodPiece = woodGraph:PlaceRoot("FoundationSquare", CFrame.new())
    woodLifecycle:EnsurePiece(woodPiece)
    local woodHit = woodLifecycle:ApplyDamage(woodPiece.id, 100, "Melee", "verify:wood-hit")

    local metalGraph = BuildGraph.new()
    local metalLifecycle = PieceLifecycle.new(metalGraph, { maxHistory = 32 })
    local metalPiece = metalGraph:PlaceRoot("FoundationSquare", CFrame.new())
    metalPiece.materialGrade = "Metal"
    metalPiece.health = nil
    metalPiece.maxHealth = nil
    metalLifecycle:EnsurePiece(metalPiece)
    local metalHit = metalLifecycle:ApplyDamage(metalPiece.id, 100, "Melee", "verify:metal-hit")
    check(
        woodHit.ok
            and metalHit.ok
            and metalHit.appliedDamage < woodHit.appliedDamage
            and metalPiece.maxHealth > woodPiece.maxHealth,
        "higherGradeImprovesDurability",
        results
    )

    local destroyGraph = BuildGraph.new()
    local destroyLifecycle = PieceLifecycle.new(destroyGraph, { maxHistory = 32 })
    local destroyPiece = destroyGraph:PlaceRoot("FoundationSquare", CFrame.new())
    destroyLifecycle:EnsurePiece(destroyPiece)
    local destroyed = destroyLifecycle:ApplyDamage(
        destroyPiece.id,
        destroyPiece.maxHealth * 10,
        "Explosion",
        "verify:destroy"
    )
    check(
        destroyed.ok
            and destroyed.destroyed
            and destroyPiece.health == 0
            and destroyPiece.destroyed == true,
        "healthNeverNegative",
        results
    )

    local demolishGraph = BuildGraph.new()
    local demolishLifecycle = PieceLifecycle.new(demolishGraph, { maxHistory = 32 })
    local demolishPiece = demolishGraph:PlaceRoot("FoundationSquare", CFrame.new())
    demolishLifecycle:EnsurePiece(demolishPiece)
    local refundWallet = makeEconomy({})
    local refundPreview = demolishLifecycle:PreviewDemolish(demolishPiece.id)
    local removedCalls = 0
    local function removeCallback(pieceId)
        removedCalls += 1
        return demolishGraph:Remove(pieceId)
    end
    local demolished = demolishLifecycle:Demolish(
        demolishPiece.id,
        refundWallet,
        "verify:demolish",
        removeCallback
    )
    local refundedWood = refundWallet.deposited.Wood or 0
    local duplicateDemolish = demolishLifecycle:Demolish(
        demolishPiece.id,
        refundWallet,
        "verify:demolish",
        removeCallback
    )
    check(
        refundPreview ~= nil
            and demolished.ok
            and demolished.refunded
            and demolished.refund.Wood > 0
            and near(refundedWood, demolished.refund.Wood)
            and duplicateDemolish.duplicate
            and removedCalls == 1
            and near(refundWallet.deposited.Wood or 0, refundedWood),
        "demolishRefundIdempotent",
        results
    )

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    local stats = lifecycle:GetStats()
    return passed, results, {
        finalGrade = piece.materialGrade,
        finalHealth = piece.health,
        finalMaxHealth = piece.maxHealth,
        upgrades = stats.upgrades,
        repairs = stats.repairs,
        duplicates = stats.duplicates,
        refundedWood = refundedWood,
    }
end

return B1Verifier

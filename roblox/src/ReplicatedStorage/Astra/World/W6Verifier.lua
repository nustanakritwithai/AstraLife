local WorldGrid = require(script.Parent.WorldGrid)
local WorldResourceTransaction = require(script.Parent.WorldResourceTransaction)
local SurvivalTransaction = require(script.Parent.SurvivalTransaction)
local Astra = script.Parent.Parent
local Inventory = require(Astra.Inventory)
local ResourceEconomy = require(Astra.ResourceEconomy)

local W6Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function makeGrid()
    local grid = WorldGrid.new({
        width = 3,
        depth = 1,
        cellSize = 10,
        origin = Vector3.zero,
    })
    grid:UpdateCell(1, 1, {
        biome = "Plains",
        walkable = true,
        food = 4,
        foodCapacity = 4,
        wood = 4,
        woodCapacity = 4,
        water = 0.20,
        moisture = 0.60,
        waterPotential = 0.30,
        danger = 0,
        hazardDanger = 0,
        hazardBlocked = false,
    })
    grid:UpdateCell(2, 1, {
        biome = "Forest",
        walkable = true,
        food = 5,
        foodCapacity = 5,
        wood = 6,
        woodCapacity = 6,
        water = 0,
        moisture = 0.60,
        waterPotential = 0.95,
        danger = 0,
        hazardDanger = 0,
        hazardBlocked = false,
    })
    grid:UpdateCell(3, 1, {
        biome = "Plains",
        walkable = true,
        food = 5,
        foodCapacity = 5,
        wood = 5,
        woodCapacity = 5,
        water = 0.4,
        moisture = 0.7,
        waterPotential = 0.9,
        danger = 0,
        hazardDanger = 0.9,
        hazardBlocked = true,
    })
    return grid
end

function W6Verifier.Run()
    local results = {}
    local grid = makeGrid()
    local ledger = WorldResourceTransaction.new(grid, nil, { maxHistory = 64 })
    local survival = SurvivalTransaction.new(grid, nil, ledger, {
        waterUnit = 0.05,
        springMoistureCost = 0.08,
        springThreshold = 0.85,
        maxHistory = 64,
    })

    local foodBefore = grid:ReadCell(1, 1).food
    local eat = survival:ConsumeFood(1, 1, "verify:eat")
    local foodAfter = grid:ReadCell(1, 1).food
    local duplicateEat = survival:ConsumeFood(1, 1, "verify:eat")
    check(
        eat.ok
            and eat.actual == 1
            and foodBefore - foodAfter == 1
            and duplicateEat.ok
            and duplicateEat.duplicate
            and grid:ReadCell(1, 1).food == foodAfter,
        "foodTransactionIdempotent",
        results
    )

    local waterBefore = grid:ReadCell(1, 1).water
    local drink = survival:DrinkWater(1, 1, "verify:drink-surface")
    local waterAfter = grid:ReadCell(1, 1).water
    local duplicateDrink = survival:DrinkWater(1, 1, "verify:drink-surface")
    check(
        drink.ok
            and drink.source == "surface_water"
            and math.abs((waterBefore - waterAfter) - 0.05) < 1e-6
            and duplicateDrink.duplicate
            and math.abs(grid:ReadCell(1, 1).water - waterAfter) < 1e-6,
        "surfaceWaterConserved",
        results
    )

    local moistureBefore = grid:ReadCell(2, 1).moisture
    local spring = survival:DrinkWater(2, 1, "verify:drink-spring")
    local moistureAfter = grid:ReadCell(2, 1).moisture
    check(
        spring.ok
            and spring.source == "spring_groundwater"
            and math.abs((moistureBefore - moistureAfter) - 0.08) < 1e-6,
        "springUsesMoistureReservoir",
        results
    )

    local inventory = Inventory.new(2)
    local harvestBefore = grid:ReadCell(2, 1).food
    local harvest = survival:Harvest(2, 1, "Food", 99, inventory:GetFree(), "verify:harvest")
    local accepted = inventory:Add("Food", harvest.actual)
    local harvestAfter = grid:ReadCell(2, 1).food
    check(
        harvest.ok
            and harvest.actual == 2
            and accepted == 2
            and inventory:GetTotal() == 2
            and math.abs((harvestBefore - harvestAfter) - inventory:Get("Food")) < 1e-6,
        "harvestBoundedByInventory",
        results
    )

    local duplicateHarvest = survival:Harvest(2, 1, "Food", 99, inventory:GetFree(), "verify:harvest")
    check(
        duplicateHarvest.duplicate
            and grid:ReadCell(2, 1).food == harvestAfter,
        "harvestRetryNoDoubleWithdraw",
        results
    )

    local colony = Instance.new("Folder")
    ResourceEconomy.Ensure(colony, 10)
    local carried = inventory:Get("Food")
    local deposited = ResourceEconomy.DepositToStorage(colony, "Food", carried)
    local removed = inventory:Remove("Food", deposited)
    check(
        deposited == carried
            and removed == deposited
            and inventory:Get("Food") == 0
            and ResourceEconomy.Get(colony, "Food") == deposited,
        "inventoryToColonyConserved",
        results
    )
    local colonyFood = ResourceEconomy.Get(colony, "Food")
    colony:Destroy()

    local unsafeFood = survival:ConsumeFood(3, 1, "verify:unsafe-food")
    local unsafeWater = survival:DrinkWater(3, 1, "verify:unsafe-water")
    check(
        not unsafeFood.ok
            and unsafeFood.reason == "unsafe_source"
            and not unsafeWater.ok
            and unsafeWater.reason == "unsafe_source",
        "unsafeWorldSourceRejected",
        results
    )

    local woodBefore = grid:ReadCell(1, 1).wood
    local woodHarvest = survival:Harvest(1, 1, "Wood", 999, 1, "verify:wood")
    local woodAfter = grid:ReadCell(1, 1).wood
    check(
        woodHarvest.ok
            and woodHarvest.actual == 1
            and woodAfter >= 0
            and math.abs((woodBefore - woodAfter) - 1) < 1e-6,
        "resourcesNeverNegative",
        results
    )

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results, {
        foodAfter = foodAfter,
        waterAfter = waterAfter,
        inventoryFood = inventory:Get("Food"),
        colonyFood = colonyFood,
        committed = survival:GetStats().committed,
        duplicates = survival:GetStats().duplicates,
    }
end

return W6Verifier

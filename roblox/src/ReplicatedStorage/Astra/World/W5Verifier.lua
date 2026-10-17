local WorldGrid = require(script.Parent.WorldGrid)
local AffordancePolicy = require(script.Parent.AffordancePolicy)
local DynamicNavigation = require(script.Parent.DynamicNavigation)

local W5Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

local function makeGrid(width, depth)
    local grid = WorldGrid.new({
        width = width,
        depth = depth,
        cellSize = 10,
        origin = Vector3.zero,
    })

    for z = 1, depth do
        for x = 1, width do
            grid:UpdateCell(x, z, {
                biome = "Plains",
                walkable = true,
                slope = 0.05,
                water = 0,
                waterPotential = 0.2,
                food = 2,
                wood = 3,
                danger = 0,
                hazardDanger = 0,
                hazardBlocked = false,
            })
        end
    end
    return grid
end

local function pathContains(path, x, z)
    for _, node in ipairs(path and path.cells or {}) do
        if node.x == x and node.z == z then
            return true
        end
    end
    return false
end

function W5Verifier.Run()
    local results = {}

    local safeWater = makeGrid(1, 1)
    safeWater:UpdateCell(1, 1, { water = 0.6 })
    local allowedWater, waterReason = AffordancePolicy.Evaluate(safeWater:ReadCell(1, 1), "Drink")
    check(allowedWater and waterReason == "ok", "safeWaterDrinkable", results)

    local unsafeWater = makeGrid(1, 1)
    unsafeWater:UpdateCell(1, 1, {
        water = 0.8,
        hazardDanger = 0.9,
        hazardBlocked = true,
    })
    local unsafeDrink, unsafeReason = AffordancePolicy.Evaluate(unsafeWater:ReadCell(1, 1), "Drink")
    check(not unsafeDrink and unsafeReason == "unsafe_water", "waterExistsButUnsafe", results)

    local springGrid = makeGrid(1, 1)
    springGrid:UpdateCell(1, 1, { water = 0, waterPotential = 0.92 })
    local springDrink = AffordancePolicy.Evaluate(springGrid:ReadCell(1, 1), "Drink")
    check(springDrink == true, "springPotentialDrinkable", results)

    local routeGrid = makeGrid(5, 3)
    local navigation = DynamicNavigation.new(routeGrid, {
        maxExpanded = 64,
        maxReplans = 2,
    })
    local route, routeError = navigation:PlanCells(1, 2, 5, 2)
    check(route ~= nil and routeError == nil and #route.cells == 5, "deterministicShortestRoute", results)
    check(route and pathContains(route, 3, 2), "initialRouteUsesCenter", results)

    routeGrid:UpdateCell(3, 2, {
        hazardDanger = 0.95,
        hazardBlocked = true,
        dominantHazard = "Fire",
    })
    local invalid = navigation:Revalidate(route, 1)
    check(
        invalid.valid == false
            and invalid.reason == "hazard_blocked"
            and invalid.invalidKey == "3:2",
        "routeInvalidatesOnHazard",
        results
    )

    local replanned, replanError = navigation:Replan(route, 1, 2)
    check(replanned ~= nil and replanError == nil, "routeReplans", results)
    check(
        replanned ~= nil
            and not pathContains(replanned, 3, 2)
            and replanned.replans == 1,
        "replanAvoidsHazard",
        results
    )

    if replanned and #replanned.cells >= 2 then
        local changedNode = replanned.cells[2]
        routeGrid:UpdateCell(changedNode.x, changedNode.z, { danger = 0.10 })
        local stillValid = navigation:Revalidate(replanned, 1)
        check(
            stillValid.valid == true
                and stillValid.reason == "changed_but_valid"
                and stillValid.changedCells >= 1,
            "changedCellRevalidatedInsteadOfBlindInvalidation",
            results
        )
    else
        check(false, "changedCellRevalidatedInsteadOfBlindInvalidation", results)
    end

    local blockedGrid = makeGrid(5, 3)
    for z = 1, 3 do
        blockedGrid:UpdateCell(3, z, {
            hazardDanger = 1,
            hazardBlocked = true,
        })
    end
    local boundedNavigation = DynamicNavigation.new(blockedGrid, { maxExpanded = 4 })
    local noRoute, noRouteReason = boundedNavigation:PlanCells(1, 2, 5, 2, { maxExpanded = 4 })
    check(noRoute == nil and noRouteReason == "search_budget_exhausted", "searchBudgetBounded", results)

    local budgetPath = replanned
    if budgetPath then
        budgetPath.replans = 2
    end
    local budgetRoute, budgetReason = navigation:Replan(budgetPath, 1, 2, { maxReplans = 2 })
    check(budgetRoute == nil and budgetReason == "replan_budget_exhausted", "replanBudgetBounded", results)

    local pathA, pathAError = DynamicNavigation.new(makeGrid(5, 3), { maxExpanded = 64 }):PlanCells(1, 2, 5, 2)
    local pathB, pathBError = DynamicNavigation.new(makeGrid(5, 3), { maxExpanded = 64 }):PlanCells(1, 2, 5, 2)
    check(
        pathAError == nil
            and pathBError == nil
            and DynamicNavigation.PathFingerprint(pathA) == DynamicNavigation.PathFingerprint(pathB),
        "deterministicPathFingerprint",
        results
    )

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    local stats = navigation:GetStats()
    return passed, results, {
        routeFingerprint = route and route.fingerprint or "00000000",
        replanFingerprint = replanned and replanned.fingerprint or "00000000",
        plans = stats.plans,
        replans = stats.replans,
        invalidations = stats.invalidations,
        expanded = stats.expanded,
    }
end

return W5Verifier

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local ResourceEconomy = require(Astra.ResourceEconomy)
local AffordanceNavigationService = require(script.Parent.AffordanceNavigationService)
local LivingResourceService = require(script.Parent.LivingResourceService)
local WorldModules = Astra:WaitForChild("World")
local SurvivalTransaction = require(WorldModules.SurvivalTransaction)
local W6Verifier = require(WorldModules.W6Verifier)

local SurvivalBridgeService = {}

local started = false
local result = nil
local routes = {}
local depositSeen = {}
local depositOrder = {}
local maxDepositHistory = 2048

local ACTION_BY_RESOURCE = {
    Food = "Eat",
    Water = "Drink",
    Wood = "HarvestWood",
}

local function routeKey(actorKey, resourceType)
    return tostring(actorKey) .. ":" .. tostring(resourceType)
end

local function rememberDeposit(id, value)
    depositSeen[id] = value
    table.insert(depositOrder, id)
    while #depositOrder > maxDepositHistory do
        local expired = table.remove(depositOrder, 1)
        depositSeen[expired] = nil
    end
end

local function publishStats(current)
    local stats = current.transactions:GetStats()
    local state = current.runtime.state
    state:SetAttribute("W6TransactionsCommitted", stats.committed)
    state:SetAttribute("W6TransactionsRejected", stats.rejected)
    state:SetAttribute("W6TransactionsDuplicate", stats.duplicates)
    state:SetAttribute("W6FoodConsumed", stats.foodConsumed)
    state:SetAttribute("W6SurfaceWaterConsumed", stats.surfaceWaterConsumed)
    state:SetAttribute("W6SpringWaterConsumed", stats.springWaterConsumed)
    state:SetAttribute("W6FoodHarvested", stats.foodHarvested)
    state:SetAttribute("W6WoodHarvested", stats.woodHarvested)
    state:SetAttribute("W6ActiveRoutes", (function()
        local count = 0
        for _ in pairs(routes) do count += 1 end
        return count
    end)())
end

local function sourceScore(cell, resourceType, distanceSquared)
    local danger = math.max(cell.danger or 0, cell.hazardDanger or 0)
    local quantity = 0
    if resourceType == "Food" then
        quantity = cell.food or 0
    elseif resourceType == "Wood" then
        quantity = cell.wood or 0
    elseif resourceType == "Water" then
        quantity = (cell.water or 0) * 20 + (cell.waterPotential or 0) * 2
    end
    return quantity * 10 - danger * 12 - distanceSquared * 0.025
end

local function sourceHasTransactionalQuantity(current, cell, resourceType)
    if resourceType ~= "Water" then return true end
    local tx = current.transactions
    return (cell.water or 0) >= tx.waterUnit
        or (
            (cell.waterPotential or 0) >= tx.springThreshold
            and (cell.moisture or 0) >= tx.springMoistureCost
        )
end

local function findSource(current, originPosition, resourceType, radiusCells)
    local grid = current.runtime.grid
    local originX, originZ = grid:WorldToCell(originPosition)
    if not originX then return nil, "outside_world" end

    radiusCells = math.max(1, math.floor(radiusCells or 14))
    local action = ACTION_BY_RESOURCE[resourceType]
    if not action then return nil, "unsupported_resource" end

    local best = nil
    for z = math.max(1, originZ - radiusCells), math.min(grid.depth, originZ + radiusCells) do
        for x = math.max(1, originX - radiusCells), math.min(grid.width, originX + radiusCells) do
            local cell = grid:ReadCell(x, z)
            local allowed = current.runtime.affordancePolicy.Evaluate(cell, action)
            if allowed and sourceHasTransactionalQuantity(current, cell, resourceType) then
                local dx = x - originX
                local dz = z - originZ
                local distanceSquared = dx * dx + dz * dz
                local score = sourceScore(cell, resourceType, distanceSquared)
                local better = best == nil
                    or score > best.score
                    or (score == best.score and distanceSquared < best.distanceSquared)
                    or (score == best.score and distanceSquared == best.distanceSquared and z < best.z)
                    or (score == best.score and distanceSquared == best.distanceSquared and z == best.z and x < best.x)
                if better then
                    best = {
                        x = x,
                        z = z,
                        key = grid:Key(x, z),
                        position = grid:CellCenter(x, z),
                        score = score,
                        distanceSquared = distanceSquared,
                    }
                end
            end
        end
    end
    return best, best and nil or "no_source"
end

local function nextWaypoint(current, path, currentPosition)
    local grid = current.runtime.grid
    local currentX, currentZ = grid:WorldToCell(currentPosition)
    if not currentX then return nil end
    local currentKey = grid:Key(currentX, currentZ)
    local index = nil
    for i, node in ipairs(path.cells or {}) do
        if node.key == currentKey then index = i break end
    end
    if not index then
        index = 1
    end
    local node = path.cells[math.min(#path.cells, index + 1)]
    if not node then return nil end
    return grid:CellCenter(node.x, node.z), node
end

function SurvivalBridgeService.Start()
    if started then return result end
    started = true

    local navResult = AffordanceNavigationService.Start()
    local livingResult = LivingResourceService.Start()
    local runtime = navResult.runtime
    local state = runtime.state
    state:SetAttribute("Version", "W6")
    state:SetAttribute("W6Status", "BOOTING")

    local transactions = SurvivalTransaction.new(
        runtime.grid,
        runtime.dirty,
        livingResult.ledger,
        {
            waterUnit = 0.05,
            springMoistureCost = 0.08,
            springThreshold = 0.85,
            maxHistory = 2048,
        }
    )
    runtime.survivalTransactions = transactions

    local passed, checks, verifierStats = W6Verifier.Run()
    state:SetAttribute("W6Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W6Check_" .. name, value)
    end
    state:SetAttribute("W6VerifierFoodAfter", verifierStats.foodAfter)
    state:SetAttribute("W6VerifierWaterAfter", verifierStats.waterAfter)
    state:SetAttribute("W6VerifierInventoryFood", verifierStats.inventoryFood)
    state:SetAttribute("W6VerifierColonyFood", verifierStats.colonyFood)

    result = {
        runtime = runtime,
        transactions = transactions,
        navigation = navResult.navigation,
        passed = passed,
        checks = checks,
    }
    publishStats(result)

    runtime.clock:RegisterSystem("W6.TransactionDiagnostics", 4, function()
        publishStats(result)
    end, 700)

    runtime.events:Emit("world.survival-bridge.started", {
        waterUnit = transactions.waterUnit,
        maxHistory = transactions.maxHistory,
    }, runtime.clock.tick)

    return result
end

function SurvivalBridgeService.FindSource(originPosition, resourceType, radiusCells)
    local current = SurvivalBridgeService.Start()
    return findSource(current, originPosition, resourceType, radiusCells)
end

function SurvivalBridgeService.Navigate(actorKey, currentPosition, resourceType, radiusCells)
    local current = SurvivalBridgeService.Start()
    local key = routeKey(actorKey, resourceType)
    local source, reason = findSource(current, currentPosition, resourceType, radiusCells)
    if not source then
        routes[key] = nil
        return { ok = false, reason = reason }
    end

    local currentX, currentZ = current.runtime.grid:WorldToCell(currentPosition)
    if currentX == source.x and currentZ == source.z then
        routes[key] = nil
        return {
            ok = true,
            atSource = true,
            source = source,
            nextPosition = source.position,
        }
    end

    local entry = routes[key]
    local path = entry and entry.path or nil
    if entry and entry.sourceKey ~= source.key then
        path = nil
    end

    if path then
        local validation = AffordanceNavigationService.Revalidate(path, 1)
        if not validation.valid then
            local replanned, replanReason = AffordanceNavigationService.ReplanWorld(path, currentPosition)
            if replanned then
                path = replanned
            else
                path = nil
                reason = replanReason
            end
        end
    end

    if not path then
        local planned, planReason = AffordanceNavigationService.PlanWorld(currentPosition, source.position)
        if not planned then
            routes[key] = nil
            return { ok = false, reason = planReason or reason or "no_route", source = source }
        end
        path = planned
    end

    routes[key] = { path = path, sourceKey = source.key }
    local nextPosition, nextNode = nextWaypoint(current, path, currentPosition)
    return {
        ok = nextPosition ~= nil,
        atSource = false,
        source = source,
        path = path,
        nextPosition = nextPosition,
        nextNode = nextNode,
        reason = nextPosition and nil or "no_waypoint",
    }
end

function SurvivalBridgeService.TryEat(actorKey, position, transactionId)
    local current = SurvivalBridgeService.Start()
    local x, z = current.runtime.grid:WorldToCell(position)
    if not x then return { ok = false, reason = "outside_world" } end
    local allowed, reason = current.runtime.affordancePolicy.Evaluate(current.runtime.grid:ReadCell(x, z), "Eat")
    if not allowed then return { ok = false, reason = reason } end
    local tx = current.transactions:ConsumeFood(x, z, transactionId)
    if tx.ok and not tx.duplicate then routes[routeKey(actorKey, "Food")] = nil end
    publishStats(current)
    return tx
end

function SurvivalBridgeService.TryDrink(actorKey, position, transactionId)
    local current = SurvivalBridgeService.Start()
    local x, z = current.runtime.grid:WorldToCell(position)
    if not x then return { ok = false, reason = "outside_world" } end
    local cell = current.runtime.grid:ReadCell(x, z)
    local allowed, reason = current.runtime.affordancePolicy.Evaluate(cell, "Drink")
    if not allowed then return { ok = false, reason = reason } end
    if not sourceHasTransactionalQuantity(current, cell, "Water") then
        return { ok = false, reason = "insufficient_water_reservoir" }
    end
    local tx = current.transactions:DrinkWater(x, z, transactionId)
    if tx.ok and not tx.duplicate then routes[routeKey(actorKey, "Water")] = nil end
    publishStats(current)
    return tx
end

function SurvivalBridgeService.HarvestToInventory(actorKey, inventory, position, resourceType, amount, transactionId)
    local current = SurvivalBridgeService.Start()
    local x, z = current.runtime.grid:WorldToCell(position)
    if not x then return { ok = false, reason = "outside_world" } end
    local action = resourceType == "Food" and "Forage" or (resourceType == "Wood" and "HarvestWood" or nil)
    if not action then return { ok = false, reason = "unsupported_resource" } end
    local allowed, reason = current.runtime.affordancePolicy.Evaluate(current.runtime.grid:ReadCell(x, z), action)
    if not allowed then return { ok = false, reason = reason } end

    local free = inventory and inventory:GetFree() or 0
    local tx = current.transactions:Harvest(x, z, resourceType, amount, free, transactionId)
    if tx.ok and not tx.duplicate then
        local accepted = inventory:Add(resourceType, tx.actual)
        assert(math.abs(accepted - tx.actual) < 1e-6, "W6 inventory reservation invariant violated")
        routes[routeKey(actorKey, resourceType)] = nil
    end
    publishStats(current)
    return tx
end

function SurvivalBridgeService.DepositInventory(actorKey, inventory, colonyState, transactionId)
    SurvivalBridgeService.Start()
    transactionId = tostring(transactionId or ("deposit:" .. tostring(actorKey)))
    local previous = depositSeen[transactionId]
    if previous then
        local copy = {}
        for key, value in pairs(previous) do copy[key] = value end
        copy.duplicate = true
        return copy
    end

    ResourceEconomy.Ensure(colonyState)
    local deposited = {}
    local total = 0
    for resourceType, amount in pairs(inventory:Snapshot()) do
        local accepted = ResourceEconomy.DepositToStorage(colonyState, resourceType, amount)
        if accepted > 0 then
            local removed = inventory:Remove(resourceType, accepted)
            assert(math.abs(removed - accepted) < 1e-6, "W6 colony transfer invariant violated")
            deposited[resourceType] = accepted
            total += accepted
        end
    end

    local resultValue = {
        ok = total > 0,
        duplicate = false,
        transactionId = transactionId,
        total = total,
        deposited = deposited,
    }
    rememberDeposit(transactionId, resultValue)
    return resultValue
end

function SurvivalBridgeService.GetResult()
    return result
end

function SurvivalBridgeService.IsStarted()
    return started
end

return SurvivalBridgeService

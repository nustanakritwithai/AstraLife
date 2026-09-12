local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Config = require(Astra.Config)
local ResourceEconomy = require(Astra.ResourceEconomy)
local AffordanceNavigationService = require(script.Parent.AffordanceNavigationService)
local LivingResourceService = require(script.Parent.LivingResourceService)
local WorldModules = Astra:WaitForChild("World")
local SurvivalTransaction = require(WorldModules.SurvivalTransaction)
local W6Verifier = require(WorldModules.W6Verifier)
local AffordancePolicy = require(WorldModules.AffordancePolicy)
local InventoryShadow = require(Astra.SurvivalCrafting.Adapter.InventoryShadow)
local SurfaceResolver = require(WorldModules.SurfaceResolver)
local SurfaceResolverContract = require(WorldModules.SurfaceResolverContract)

local SurvivalBridgeService = {}

local started = false
local result = nil
local routes = {}
local depositSeen = {}
local depositOrder = {}
local maxDepositHistory = 2048

-- I0.2: delegate physical Y projection to the shared World SurfaceResolver.
-- Do not keep a private SurvivalBridge projector (I0.2 / I5 gate).
local function projectToPhysicalSurface(position)
    return SurfaceResolver.Project(position)
end

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

-- I0.4: bounded deterministic candidate list instead of a single best source,
-- so an unreachable top source can be skipped within a route-attempt budget.
local function collectSourceCandidates(current, originPosition, resourceType, radiusCells, maxCandidates)
    local grid = current.runtime.grid
    local originX, originZ = grid:WorldToCell(originPosition)
    if not originX then return nil, "outside_world" end

    radiusCells = math.max(1, math.floor(radiusCells or 14))
    local action = ACTION_BY_RESOURCE[resourceType]
    if not action then return nil, "unsupported_resource" end

    local candidates = {}
    for z = math.max(1, originZ - radiusCells), math.min(grid.depth, originZ + radiusCells) do
        for x = math.max(1, originX - radiusCells), math.min(grid.width, originX + radiusCells) do
            local cell = grid:ReadCell(x, z)
            local allowed = current.runtime.affordancePolicy.Evaluate(cell, action)
            if allowed and sourceHasTransactionalQuantity(current, cell, resourceType) then
                local dx = x - originX
                local dz = z - originZ
                local distanceSquared = dx * dx + dz * dz
                table.insert(candidates, {
                    x = x,
                    z = z,
                    key = grid:Key(x, z),
                    position = grid:CellCenter(x, z),
                    score = sourceScore(cell, resourceType, distanceSquared),
                    distanceSquared = distanceSquared,
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.distanceSquared ~= b.distanceSquared then return a.distanceSquared < b.distanceSquared end
        if a.z ~= b.z then return a.z < b.z end
        return a.x < b.x
    end)

    while #candidates > (maxCandidates or 8) do
        table.remove(candidates)
    end
    return candidates, #candidates > 0 and nil or "no_source"
end

local function findSource(current, originPosition, resourceType, radiusCells)
    local candidates, reason = collectSourceCandidates(current, originPosition, resourceType, radiusCells, 1)
    return candidates and candidates[1] or nil, reason
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
    return projectToPhysicalSurface(grid:CellCenter(node.x, node.z)), node
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

    local surfacePassed, surfaceChecks, surfaceStats = SurfaceResolverContract.Run()
    state:SetAttribute("I02SurfaceResolverStatus", surfacePassed and "PASS" or "FAIL")
    for name, value in pairs(surfaceChecks) do
        state:SetAttribute("I02SurfaceCheck_" .. name, value)
    end
    if surfaceStats and surfaceStats.resolvedY ~= nil then
        state:SetAttribute("I02SurfaceResolvedY", surfaceStats.resolvedY)
    end
    if surfaceStats and surfaceStats.defaultExcludeNames then
        state:SetAttribute("I02SurfaceDefaultExclude", surfaceStats.defaultExcludeNames)
    end
    if not surfacePassed then
        state:SetAttribute("W6Status", "FAIL")
    end

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
    local candidates, reason = collectSourceCandidates(current, currentPosition, resourceType, radiusCells, 8)
    if not candidates or #candidates == 0 then
        routes[key] = nil
        return { ok = false, reason = reason or "no_source" }
    end

    local grid = current.runtime.grid
    local currentX, currentZ = grid:WorldToCell(currentPosition)

    -- I0.4: deterministic candidate order, bounded W5 route-attempt budget,
    -- cached successful source/route on the first attempt only.
    local attempts = math.min(#candidates, Config.W6RouteAttemptBudget or 3)
    for attempt = 1, attempts do
        local source = candidates[attempt]

        if currentX == source.x and currentZ == source.z then
            routes[key] = nil
            return {
                ok = true,
                atSource = true,
                source = source,
                nextPosition = projectToPhysicalSurface(source.position),
            }
        end

        local path = nil
        local entry = routes[key]
        if attempt == 1 and entry and entry.sourceKey == source.key then
            path = entry.path
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
            if planned then
                path = planned
            else
                reason = planReason or "unreachable_source"
            end
        end

        if path then
            routes[key] = { path = path, sourceKey = source.key, source = source }
            local nextPosition, nextNode = nextWaypoint(current, path, currentPosition)
            return {
                ok = nextPosition ~= nil,
                atSource = false,
                source = source,
                path = path,
                nextPosition = nextPosition,
                nextNode = nextNode,
                attempts = attempt,
                reason = nextPosition and nil or "no_waypoint",
            }
        end
    end

    routes[key] = nil
    return { ok = false, reason = reason or "no_route", attempts = attempts }
end

local HAZARD_KINDS = {
    { key = "fireIntensity", name = "fire" },
    { key = "floodSeverity", name = "flood" },
    { key = "droughtSeverity", name = "drought" },
    { key = "stormSeverity", name = "storm" },
}

local function dominantHazard(cell)
    local bestName, bestValue = "none", 0
    for _, hazard in ipairs(HAZARD_KINDS) do
        local value = math.clamp(cell[hazard.key] or 0, 0, 1)
        if value > bestValue then
            bestName = hazard.name
            bestValue = value
        end
    end
    return bestName
end

-- I0.1: single W-series danger observation for the P-side survival brain.
-- P4 never becomes a second hazard authority; it only reads this projection.
function SurvivalBridgeService.ObserveEnvironment(position)
    local current = SurvivalBridgeService.Start()
    local grid = current.runtime.grid
    local x, z = grid:WorldToCell(position)
    if not x then
        return {
            inWorld = false,
            baseDanger = 0,
            hazardDanger = 0,
            ecosystemDanger = 0,
            effectiveDanger = 0,
            dominantHazard = "none",
            hazardBlocked = false,
            walkable = false,
        }
    end

    local cell = grid:ReadCell(x, z)
    local hazardBlocked = cell.hazardBlocked == true
    local observation = {
        inWorld = true,
        cellKey = grid:Key(x, z),
        baseDanger = math.clamp(cell.danger or 0, 0, 1),
        hazardDanger = math.clamp(cell.hazardDanger or 0, 0, 1),
        ecosystemDanger = math.clamp(cell.ecosystemDanger or 0, 0, 1),
        dominantHazard = dominantHazard(cell),
        hazardBlocked = hazardBlocked,
        walkable = cell.walkable == true,
    }
    observation.effectiveDanger = math.max(
        AffordancePolicy.EffectiveDanger(cell),
        hazardBlocked and 1 or 0
    )
    return observation
end

-- I0.1: flee requests a safe logical W5 route; Roblox path execution happens
-- agent-side against real geometry.
function SurvivalBridgeService.Escape(currentPosition)
    local current = SurvivalBridgeService.Start()
    local runtime = current.runtime
    local safe = runtime.query:FindBestCell(currentPosition, Config.WorldEscapeRadiusCells, function(cell)
        if cell.hazardBlocked == true or cell.walkable ~= true then return nil end
        local danger = AffordancePolicy.EffectiveDanger(cell)
        if danger >= (Config.WorldDangerFleeThreshold or 0.5) then return nil end
        return 1 - danger
    end)
    if not safe then return { ok = false, reason = "no_safe_cell" } end

    local path, reason = AffordanceNavigationService.PlanWorld(currentPosition, safe.position)
    if not path then
        return { ok = false, reason = reason or "no_escape_route" }
    end

    local nextPosition = nextWaypoint(current, path, currentPosition)
    return {
        ok = true,
        nextPosition = nextPosition or projectToPhysicalSurface(safe.position),
        target = projectToPhysicalSurface(safe.position),
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
    local grid = current.runtime.grid
    local x, z = grid:WorldToCell(position)
    if not x then return { ok = false, reason = "outside_world" } end
    local action = resourceType == "Food" and "Forage" or (resourceType == "Wood" and "HarvestWood" or nil)
    if not action then return { ok = false, reason = "unsupported_resource" } end
    local allowed, reason = current.runtime.affordancePolicy.Evaluate(grid:ReadCell(x, z), action)
    if not allowed then return { ok = false, reason = reason } end

    local free = inventory and inventory:GetFree() or 0
    local tx = current.transactions:Harvest(x, z, resourceType, amount, free, transactionId)
    if tx.ok and not tx.duplicate then
        -- I3: committed W6 withdrawal → WorldGatherReceipt → Convert → S4, then
        -- project LivingWorld units onto legacy Carry_*. Eat/Drink are not shadowed.
        local context = resourceType == "Food" and { source = "forage" } or {}
        local shadow, shadowReason = InventoryShadow.ApplyCommittedHarvest({
            transactionId = tx.transactionId,
            actorId = tostring(actorKey),
            worldTick = current.runtime.clock.tick,
            cellKey = grid:Key(x, z),
            worldResourceType = resourceType,
            actualWithdrawn = tx.actual,
            context = context,
            toolClass = resourceType == "Wood" and "axe" or "hand",
            toolTier = 0,
        })
        if shadow and shadow.ok then
            tx.shadow = shadow
            tx.receipt = shadow.receipt
        else
            -- W6 withdraw already committed; keep Carry projection for P and
            -- surface the shadow failure without rolling back world authority.
            tx.shadowError = tostring(shadowReason or (shadow and shadow.reason) or "unknown")
        end
        local accepted = inventory:Add(resourceType, tx.actual)
        assert(math.abs(accepted - tx.actual) < 1e-6, "W6 inventory reservation invariant violated")
        if shadow and shadow.ok then
            InventoryShadow.EnsureLegacyProjection(tostring(actorKey), inventory)
        end
        routes[routeKey(actorKey, resourceType)] = nil
    elseif tx.ok and tx.duplicate then
        -- Idempotent W6 retry: re-apply shadow (also idempotent on transactionId)
        -- so S4/Carry stay aligned without duplicating.
        local context = resourceType == "Food" and { source = "forage" } or {}
        if (tx.actual or 0) > 0 then
            InventoryShadow.ApplyCommittedHarvest({
                transactionId = tx.transactionId,
                actorId = tostring(actorKey),
                worldTick = current.runtime.clock.tick,
                cellKey = grid:Key(x, z),
                worldResourceType = resourceType,
                actualWithdrawn = tx.actual,
                context = context,
                toolClass = resourceType == "Wood" and "axe" or "hand",
                toolTier = 0,
            })
            if inventory then
                InventoryShadow.EnsureLegacyProjection(tostring(actorKey), inventory)
            end
        end
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
            -- I3: remove once from S4 + LivingWorld projection for the same units.
            InventoryShadow.RemoveLegacyProjection(
                tostring(actorKey),
                resourceType,
                accepted,
                tostring(transactionId) .. ":i3:" .. tostring(resourceType),
                resourceType == "Food" and { context = { source = "forage" } } or nil
            )
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

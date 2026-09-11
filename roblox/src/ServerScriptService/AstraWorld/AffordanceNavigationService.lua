local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DynamicHazardService = require(script.Parent.DynamicHazardService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local AffordancePolicy = require(WorldModules.AffordancePolicy)
local DynamicNavigation = require(WorldModules.DynamicNavigation)
local W5Verifier = require(WorldModules.W5Verifier)

local AffordanceNavigationService = {}

local started = false
local result = nil

local function publishStats(state, navigation)
    local stats = navigation:GetStats()
    state:SetAttribute("NavigationPlans", stats.plans)
    state:SetAttribute("NavigationPlanFailures", stats.planFailures)
    state:SetAttribute("NavigationReplans", stats.replans)
    state:SetAttribute("NavigationInvalidations", stats.invalidations)
    state:SetAttribute("NavigationExpanded", stats.expanded)
end

local function updateRouteState(state, path, reason)
    state:SetAttribute("NavigationLastReason", tostring(reason or "ok"))
    if path then
        state:SetAttribute("NavigationLastRouteId", path.id)
        state:SetAttribute("NavigationLastRouteLength", #path.cells)
        state:SetAttribute("NavigationLastRouteCost", path.cost)
        state:SetAttribute("NavigationLastRouteExpanded", path.expanded)
        state:SetAttribute("NavigationLastRouteReplans", path.replans)
        state:SetAttribute("NavigationLastRouteFingerprint", path.fingerprint)
    end
end

function AffordanceNavigationService.Start()
    if started then
        return result
    end
    started = true

    local hazardResult = DynamicHazardService.Start()
    local runtime = hazardResult.runtime
    local state = runtime.state
    state:SetAttribute("Version", "W5")
    state:SetAttribute("W5Status", "BOOTING")

    local navigation = DynamicNavigation.new(runtime.grid, {
        maxExpanded = 2048,
        maxReplans = 4,
        hazardCost = 8,
        slopeCost = 2.5,
        waterCost = 1.5,
    })

    runtime.affordancePolicy = AffordancePolicy
    runtime.navigation = navigation

    local passed, checks, verifierStats = W5Verifier.Run()
    state:SetAttribute("W5Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W5Check_" .. name, value)
    end
    state:SetAttribute("W5VerifierRouteFingerprint", verifierStats.routeFingerprint)
    state:SetAttribute("W5VerifierReplanFingerprint", verifierStats.replanFingerprint)
    state:SetAttribute("W5VerifierPlans", verifierStats.plans)
    state:SetAttribute("W5VerifierReplans", verifierStats.replans)
    state:SetAttribute("W5VerifierInvalidations", verifierStats.invalidations)
    state:SetAttribute("W5VerifierExpanded", verifierStats.expanded)

    publishStats(state, navigation)
    state:SetAttribute("NavigationLastReason", "none")
    state:SetAttribute("NavigationLastRouteFingerprint", "00000000")

    runtime.clock:RegisterSystem("W5.NavigationDiagnostics", 4, function()
        publishStats(state, navigation)
    end, 600)

    runtime.events:Emit("world.navigation.started", {
        maxExpanded = navigation.config.maxExpanded,
        maxReplans = navigation.config.maxReplans,
    }, runtime.clock.tick)

    result = {
        runtime = runtime,
        navigation = navigation,
        passed = passed,
        checks = checks,
    }
    return result
end

function AffordanceNavigationService.EvaluateAtPosition(position, action, options)
    local current = AffordanceNavigationService.Start()
    return current.runtime.query:EvaluateActionAt(position, action, options)
end

function AffordanceNavigationService.EvaluateCell(x, z, action, options)
    local current = AffordanceNavigationService.Start()
    return current.runtime.query:EvaluateCellAction(x, z, action, options)
end

function AffordanceNavigationService.GetAffordancesAt(position)
    local current = AffordanceNavigationService.Start()
    return current.runtime.query:GetAffordancesAt(position)
end

function AffordanceNavigationService.PlanCells(startX, startZ, goalX, goalZ, options)
    local current = AffordanceNavigationService.Start()
    local path, reason = current.navigation:PlanCells(startX, startZ, goalX, goalZ, options)
    publishStats(current.runtime.state, current.navigation)
    updateRouteState(current.runtime.state, path, reason)

    current.runtime.events:Emit(path and "world.navigation.planned" or "world.navigation.failed", {
        routeId = path and path.id or nil,
        fingerprint = path and path.fingerprint or nil,
        length = path and #path.cells or 0,
        reason = reason,
        startX = startX,
        startZ = startZ,
        goalX = goalX,
        goalZ = goalZ,
    }, current.runtime.clock.tick)

    return path, reason
end

function AffordanceNavigationService.PlanWorld(startPosition, goalPosition, options)
    local current = AffordanceNavigationService.Start()
    local startX, startZ = current.runtime.grid:WorldToCell(startPosition)
    local goalX, goalZ = current.runtime.grid:WorldToCell(goalPosition)
    if not startX or not goalX then
        return nil, "outside_world"
    end
    return AffordanceNavigationService.PlanCells(startX, startZ, goalX, goalZ, options)
end

function AffordanceNavigationService.Revalidate(path, fromIndex)
    local current = AffordanceNavigationService.Start()
    local validation = current.navigation:Revalidate(path, fromIndex)
    publishStats(current.runtime.state, current.navigation)
    current.runtime.state:SetAttribute("NavigationLastValidation", validation.reason)
    current.runtime.state:SetAttribute("NavigationLastChangedCells", validation.changedCells or 0)

    if not validation.valid then
        current.runtime.events:Emit("world.navigation.invalidated", {
            routeId = path and path.id or nil,
            reason = validation.reason,
            invalidIndex = validation.invalidIndex,
            invalidKey = validation.invalidKey,
            changedCells = validation.changedCells,
        }, current.runtime.clock.tick)
    end
    return validation
end

function AffordanceNavigationService.ReplanCells(path, currentX, currentZ, options)
    local current = AffordanceNavigationService.Start()
    local replanned, reason = current.navigation:Replan(path, currentX, currentZ, options)
    publishStats(current.runtime.state, current.navigation)
    updateRouteState(current.runtime.state, replanned, reason)

    current.runtime.events:Emit(replanned and "world.navigation.replanned" or "world.navigation.replan-failed", {
        previousRouteId = path and path.id or nil,
        routeId = replanned and replanned.id or nil,
        fingerprint = replanned and replanned.fingerprint or nil,
        reason = reason,
        replans = replanned and replanned.replans or (path and path.replans or 0),
    }, current.runtime.clock.tick)

    return replanned, reason
end

function AffordanceNavigationService.ReplanWorld(path, currentPosition, options)
    local current = AffordanceNavigationService.Start()
    local x, z = current.runtime.grid:WorldToCell(currentPosition)
    if not x then return nil, "outside_world" end
    return AffordanceNavigationService.ReplanCells(path, x, z, options)
end

function AffordanceNavigationService.GetResult()
    return result
end

function AffordanceNavigationService.IsStarted()
    return started
end

return AffordanceNavigationService

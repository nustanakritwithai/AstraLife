local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LivingResourceService = require(script.Parent.LivingResourceService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local HazardSystem = require(WorldModules.HazardSystem)
local LivingResourceSystem = require(WorldModules.LivingResourceSystem)
local W4Verifier = require(WorldModules.W4Verifier)

local DynamicHazardService = {}

local started = false
local result = nil

local function applyExternalResourceLoss(resources, stats)
    local totals = resources and resources.totals
    if not totals then
        return
    end
    totals.vegetation = math.max(0, (totals.vegetation or 0) - (stats.vegetationBurned or 0))
    totals.food = math.max(0, (totals.food or 0) - (stats.foodLost or 0))
    totals.wood = math.max(0, (totals.wood or 0) - (stats.woodLost or 0))
    if (stats.vegetationBurned or 0) > 0 or (stats.foodLost or 0) > 0 or (stats.woodLost or 0) > 0 then
        totals.decayedCells = (totals.decayedCells or 0) + (stats.changed or 0)
    end
end

local function publishResourceTotals(state, resources, ledger)
    local totals = resources:GetTotals()
    local transactionStats = ledger:GetStats()
    state:SetAttribute("ResourceVegetationTotal", totals.vegetation)
    state:SetAttribute("ResourceFoodTotal", math.max(0, totals.food - transactionStats.foodWithdrawn))
    state:SetAttribute("ResourceWoodTotal", math.max(0, totals.wood - transactionStats.woodWithdrawn))
end

local function summarizeHazards(grid)
    local summary = {
        fire = 0,
        flood = 0,
        drought = 0,
        storm = 0,
        blocked = 0,
        dangerSum = 0,
        maxDanger = 0,
    }

    for z = 1, grid.depth do
        for x = 1, grid.width do
            local cell = grid:ReadCell(x, z)
            local danger = cell.hazardDanger or 0
            if (cell.fireIntensity or 0) >= 0.05 then summary.fire += 1 end
            if (cell.floodSeverity or 0) >= 0.05 then summary.flood += 1 end
            if (cell.droughtSeverity or 0) >= 0.05 then summary.drought += 1 end
            if (cell.stormSeverity or 0) >= 0.05 then summary.storm += 1 end
            if cell.hazardBlocked == true then summary.blocked += 1 end
            summary.dangerSum += danger
            summary.maxDanger = math.max(summary.maxDanger, danger)
        end
    end

    local totalCells = math.max(1, grid.width * grid.depth)
    summary.averageDanger = summary.dangerSum / totalCells
    return summary
end

local function publishBatch(state, stats)
    state:SetAttribute("HazardProcessedLast", stats.processed)
    state:SetAttribute("HazardChangedLast", stats.changed)
    state:SetAttribute("HazardFireCellsLastBatch", stats.fireCells)
    state:SetAttribute("HazardFloodCellsLastBatch", stats.floodCells)
    state:SetAttribute("HazardDroughtCellsLastBatch", stats.droughtCells)
    state:SetAttribute("HazardStormCellsLastBatch", stats.stormCells)
    state:SetAttribute("HazardBlockedCellsLastBatch", stats.blockedCells)
    state:SetAttribute("HazardIgnitionsLast", stats.ignitions)
    state:SetAttribute("HazardSpreadsLast", stats.spreads)
    state:SetAttribute("HazardExtinguishedLast", stats.extinguished)
    state:SetAttribute("HazardVegetationBurnedLast", stats.vegetationBurned)
    state:SetAttribute("HazardFoodLostLast", stats.foodLost)
    state:SetAttribute("HazardWoodLostLast", stats.woodLost)
    state:SetAttribute("HazardCycle", stats.cycle)
    state:SetAttribute("HazardCursor", stats.cursor)
end

local function publishWorldSummary(state, summary)
    state:SetAttribute("HazardFireCells", summary.fire)
    state:SetAttribute("HazardFloodCells", summary.flood)
    state:SetAttribute("HazardDroughtCells", summary.drought)
    state:SetAttribute("HazardStormCells", summary.storm)
    state:SetAttribute("HazardBlockedCells", summary.blocked)
    state:SetAttribute("HazardAverageDanger", summary.averageDanger)
    state:SetAttribute("HazardMaxDanger", summary.maxDanger)
end

local function publishTotals(state, hazards)
    local totals = hazards:GetTotals()
    state:SetAttribute("HazardSteps", totals.steps)
    state:SetAttribute("HazardProcessedTotal", totals.processed)
    state:SetAttribute("HazardChangedTotal", totals.changed)
    state:SetAttribute("HazardIgnitionsTotal", totals.ignitions)
    state:SetAttribute("HazardSpreadsTotal", totals.spreads)
    state:SetAttribute("HazardExtinguishedTotal", totals.extinguished)
    state:SetAttribute("HazardVegetationBurnedTotal", totals.vegetationBurned)
    state:SetAttribute("HazardFoodLostTotal", totals.foodLost)
    state:SetAttribute("HazardWoodLostTotal", totals.woodLost)
end

function DynamicHazardService.Start()
    if started then
        return result
    end
    started = true

    local resourceResult = LivingResourceService.Start()
    local runtime = resourceResult.runtime
    local state = runtime.state
    state:SetAttribute("Version", "W4")
    state:SetAttribute("W4Status", "BOOTING")

    local hazards = HazardSystem.new(runtime.grid, {
        seed = runtime.config.seed,
        batchSize = 512,
        referenceStep = runtime.config.fixedStep * 2,
    })
    runtime.hazards = hazards

    publishWorldSummary(state, summarizeHazards(runtime.grid))
    publishTotals(state, hazards)
    state:SetAttribute("HazardFingerprint", HazardSystem.Fingerprint(runtime.grid))

    runtime.clock:RegisterSystem("W4.DynamicHazards", 2, function(context)
        local stats = hazards:Step(
            runtime.climateState,
            runtime.dirty,
            runtime.config.fixedStep * 2
        )

        applyExternalResourceLoss(resourceResult.resources, stats)
        publishResourceTotals(state, resourceResult.resources, resourceResult.ledger)
        publishBatch(state, stats)
        publishTotals(state, hazards)

        if stats.ignitions > 0 or stats.spreads > 0 or stats.extinguished > 0 then
            runtime.events:Emit("world.hazards.fire", {
                ignitions = stats.ignitions,
                spreads = stats.spreads,
                extinguished = stats.extinguished,
                vegetationBurned = stats.vegetationBurned,
                woodLost = stats.woodLost,
            }, context.tick)
        end

        if stats.cycleCompleted then
            local summary = summarizeHazards(runtime.grid)
            local fingerprint = HazardSystem.Fingerprint(runtime.grid)
            state:SetAttribute("HazardFingerprint", fingerprint)
            state:SetAttribute("ResourceFingerprint", LivingResourceSystem.Fingerprint(runtime.grid))
            publishWorldSummary(state, summary)

            runtime.events:Emit("world.hazards.cycle", {
                cycle = stats.cycle,
                fingerprint = fingerprint,
                fireCells = summary.fire,
                floodCells = summary.flood,
                droughtCells = summary.drought,
                stormCells = summary.storm,
                blockedCells = summary.blocked,
                maxDanger = summary.maxDanger,
            }, context.tick)
        end
    end, 500)

    local passed, checks, verifierStats = W4Verifier.Run()
    state:SetAttribute("W4Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W4Check_" .. name, value)
    end
    state:SetAttribute("W4VerifierFingerprint", verifierStats.fingerprint)
    state:SetAttribute("W4VerifierBatchProcessed", verifierStats.batchProcessed)

    runtime.events:Emit("world.hazards.started", {
        batchSize = hazards.config.batchSize,
        fireCells = verifierStats.fireCells,
        floodCells = verifierStats.floodCells,
        droughtCells = verifierStats.droughtCells,
        stormCells = verifierStats.stormCells,
    }, runtime.clock.tick)

    result = {
        runtime = runtime,
        hazards = hazards,
        resources = resourceResult.resources,
        ledger = resourceResult.ledger,
        passed = passed,
        checks = checks,
    }
    return result
end

function DynamicHazardService.IgniteCell(x, z, intensity)
    local current = DynamicHazardService.Start()
    local changed = current.hazards:Ignite(x, z, intensity, current.runtime.dirty)
    if changed then
        current.runtime.events:Emit("world.hazard.ignited", {
            x = x,
            z = z,
            intensity = intensity,
        }, current.runtime.clock.tick)
    end
    return changed
end

function DynamicHazardService.IgniteAtPosition(position, intensity)
    local current = DynamicHazardService.Start()
    local x, z = current.runtime.grid:WorldToCell(position)
    if not x then
        return false
    end
    return DynamicHazardService.IgniteCell(x, z, intensity)
end

function DynamicHazardService.IsStarted()
    return started
end

function DynamicHazardService.GetResult()
    return result
end

return DynamicHazardService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClimateHydrologyService = require(script.Parent.ClimateHydrologyService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local LivingResourceSystem = require(WorldModules.LivingResourceSystem)
local WorldResourceTransaction = require(WorldModules.WorldResourceTransaction)
local W3Verifier = require(WorldModules.W3Verifier)

local LivingResourceService = {}

local started = false
local result = nil

local function publishTotals(state, resources, ledger)
    local totals = resources:GetTotals()
    local transactionStats = ledger:GetStats()

    state:SetAttribute("ResourceVegetationTotal", totals.vegetation)
    state:SetAttribute("ResourceVegetationCapacity", totals.vegetationCapacity)
    state:SetAttribute("ResourceFoodTotal", math.max(0, totals.food - transactionStats.foodWithdrawn))
    state:SetAttribute("ResourceFoodCapacity", totals.foodCapacity)
    state:SetAttribute("ResourceWoodTotal", math.max(0, totals.wood - transactionStats.woodWithdrawn))
    state:SetAttribute("ResourceWoodCapacity", totals.woodCapacity)
    state:SetAttribute("ResourceCycle", totals.cycle)
    state:SetAttribute("ResourceCursor", totals.cursor)
    state:SetAttribute("ResourceSteps", totals.steps)
    state:SetAttribute("ResourceProcessedTotal", totals.processed)
    state:SetAttribute("ResourceChangedTotal", totals.changed)
    state:SetAttribute("ResourceGrewCellsTotal", totals.grewCells)
    state:SetAttribute("ResourceDecayedCellsTotal", totals.decayedCells)
    state:SetAttribute("ResourceFoodGrownTotal", totals.foodGrown)
    state:SetAttribute("ResourceWoodGrownTotal", totals.woodGrown)

    state:SetAttribute("ResourceTransactionsAccepted", transactionStats.accepted)
    state:SetAttribute("ResourceTransactionsRejected", transactionStats.rejected)
    state:SetAttribute("ResourceTransactionsDuplicate", transactionStats.duplicates)
    state:SetAttribute("ResourceFoodHarvested", transactionStats.foodWithdrawn)
    state:SetAttribute("ResourceWoodHarvested", transactionStats.woodWithdrawn)
end

local function publishStep(state, stats)
    state:SetAttribute("ResourceProcessedLast", stats.processed)
    state:SetAttribute("ResourceChangedLast", stats.changed)
    state:SetAttribute("ResourceGrewCellsLast", stats.grewCells)
    state:SetAttribute("ResourceDecayedCellsLast", stats.decayedCells)
    state:SetAttribute("ResourceVegetationDeltaLast", stats.vegetationDelta)
    state:SetAttribute("ResourceFoodDeltaLast", stats.foodDelta)
    state:SetAttribute("ResourceWoodDeltaLast", stats.woodDelta)
end

function LivingResourceService.Start()
    if started then
        return result
    end
    started = true

    local climateResult = ClimateHydrologyService.Start()
    local runtime = climateResult.runtime
    local state = runtime.state
    state:SetAttribute("Version", "W3")
    state:SetAttribute("W3Status", "BOOTING")

    local resources = LivingResourceSystem.new(runtime.grid, {
        batchSize = 512,
        referenceStep = runtime.config.fixedStep * 4,
    })
    resources:Initialize(runtime.dirty, runtime.climateState)

    local ledger = WorldResourceTransaction.new(runtime.grid, runtime.dirty, {
        maxHistory = 2048,
    })

    runtime.livingResources = resources
    runtime.resourceTransactions = ledger
    publishTotals(state, resources, ledger)
    state:SetAttribute("ResourceFingerprint", LivingResourceSystem.Fingerprint(runtime.grid))

    runtime.clock:RegisterSystem("W3.LivingResources", 4, function(context)
        local stats = resources:Step(
            runtime.climateState,
            runtime.dirty,
            runtime.config.fixedStep * 4
        )
        publishStep(state, stats)
        publishTotals(state, resources, ledger)

        if stats.cycleCompleted then
            local fingerprint = LivingResourceSystem.Fingerprint(runtime.grid)
            state:SetAttribute("ResourceFingerprint", fingerprint)
            runtime.events:Emit("world.resources.cycle", {
                cycle = stats.cycle,
                fingerprint = fingerprint,
                foodDelta = stats.foodDelta,
                woodDelta = stats.woodDelta,
                vegetationDelta = stats.vegetationDelta,
            }, context.tick)
        end
    end, 400)

    local passed, checks, verifierStats = W3Verifier.Run()
    state:SetAttribute("W3Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W3Check_" .. name, value)
    end
    state:SetAttribute("W3VerifierFingerprint", verifierStats.fingerprint)
    state:SetAttribute("W3VerifierHarvestedFood", verifierStats.harvestedFood)
    state:SetAttribute("W3VerifierDuplicateCount", verifierStats.duplicateCount)
    state:SetAttribute("W3VerifierBatchProcessed", verifierStats.batchProcessed)

    runtime.events:Emit("world.resources.started", {
        batchSize = resources.config.batchSize,
        fingerprint = state:GetAttribute("ResourceFingerprint"),
        foodCapacity = resources:GetTotals().foodCapacity,
        woodCapacity = resources:GetTotals().woodCapacity,
    }, runtime.clock.tick)

    result = {
        runtime = runtime,
        resources = resources,
        ledger = ledger,
        passed = passed,
        checks = checks,
    }
    return result
end

function LivingResourceService.WithdrawCell(x, z, resourceType, amount, transactionId)
    local current = LivingResourceService.Start()
    local withdrawal = current.ledger:Withdraw(x, z, resourceType, amount, transactionId)
    publishTotals(current.runtime.state, current.resources, current.ledger)

    if withdrawal.ok and withdrawal.actual > 0 and not withdrawal.duplicate then
        current.runtime.events:Emit("world.resource.harvested", {
            transactionId = withdrawal.transactionId,
            resourceType = withdrawal.resourceType,
            amount = withdrawal.actual,
            remaining = withdrawal.remaining,
            x = withdrawal.x,
            z = withdrawal.z,
        }, current.runtime.clock.tick)
    end

    return withdrawal
end

function LivingResourceService.WithdrawAtPosition(position, resourceType, amount, transactionId)
    local current = LivingResourceService.Start()
    local x, z = current.runtime.grid:WorldToCell(position)
    if not x then
        return {
            ok = false,
            duplicate = false,
            transactionId = tostring(transactionId or "outside-world"),
            resourceType = resourceType,
            requested = math.max(0, tonumber(amount) or 0),
            actual = 0,
            remaining = 0,
            reason = "outside_world",
        }
    end
    return LivingResourceService.WithdrawCell(x, z, resourceType, amount, transactionId)
end

function LivingResourceService.GetResult()
    return result
end

function LivingResourceService.IsStarted()
    return started
end

return LivingResourceService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivalBridgeService = require(script.Parent.SurvivalBridgeService)
local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local EcosystemSystem = require(WorldModules.EcosystemSystem)
local LivingResourceSystem = require(WorldModules.LivingResourceSystem)
local W7Verifier = require(WorldModules.W7Verifier)

local EcosystemService = {}

local started = false
local result = nil

local function applyProducerConsumption(runtime, stats)
    local resources = runtime.livingResources
    local totals = resources and resources.totals
    if not totals then return end

    totals.food = math.max(0, (totals.food or 0) - (stats.foodConsumed or 0))
    totals.vegetation = math.max(0, (totals.vegetation or 0) - (stats.vegetationConsumed or 0))
    if (stats.foodConsumed or 0) > 0 or (stats.vegetationConsumed or 0) > 0 then
        totals.decayedCells = (totals.decayedCells or 0) + (stats.changed or 0)
    end
end

local function publishResourceTotals(state, runtime)
    local resources = runtime.livingResources
    if not resources then return end
    local totals = resources:GetTotals()
    local ledger = runtime.resourceTransactions
    local transactionStats = ledger and ledger:GetStats() or { foodWithdrawn = 0, woodWithdrawn = 0 }

    state:SetAttribute("ResourceVegetationTotal", math.max(0, totals.vegetation or 0))
    state:SetAttribute("ResourceFoodTotal", math.max(0, (totals.food or 0) - (transactionStats.foodWithdrawn or 0)))
    state:SetAttribute("ResourceWoodTotal", math.max(0, (totals.wood or 0) - (transactionStats.woodWithdrawn or 0)))
end

local function publishBatch(state, stats)
    state:SetAttribute("EcosystemProcessedLast", stats.processed)
    state:SetAttribute("EcosystemChangedLast", stats.changed)
    state:SetAttribute("EcosystemFoodConsumedLast", stats.foodConsumed)
    state:SetAttribute("EcosystemVegetationConsumedLast", stats.vegetationConsumed)
    state:SetAttribute("EcosystemHerbivoreBirthsLast", stats.herbivoreBirths)
    state:SetAttribute("EcosystemHerbivoreDeathsLast", stats.herbivoreDeaths)
    state:SetAttribute("EcosystemPredatorKillsLast", stats.predatorKills)
    state:SetAttribute("EcosystemPredatorBirthsLast", stats.predatorBirths)
    state:SetAttribute("EcosystemPredatorDeathsLast", stats.predatorDeaths)
    state:SetAttribute("EcosystemScavengedLast", stats.scavenged)
    state:SetAttribute("EcosystemCarrionDecomposedLast", stats.carrionDecomposed)
    state:SetAttribute("EcosystemNutrientCreatedLast", stats.nutrientCreated)
    state:SetAttribute("EcosystemFertilityGainLast", stats.fertilityGain)
    state:SetAttribute("EcosystemCycle", stats.cycle)
    state:SetAttribute("EcosystemCursor", stats.cursor)
end

local function publishTotals(state, ecosystem)
    local totals = ecosystem:GetTotals()
    state:SetAttribute("EcosystemSteps", totals.steps)
    state:SetAttribute("EcosystemProcessedTotal", totals.processed)
    state:SetAttribute("EcosystemChangedTotal", totals.changed)
    state:SetAttribute("EcosystemFoodConsumedTotal", totals.foodConsumed)
    state:SetAttribute("EcosystemVegetationConsumedTotal", totals.vegetationConsumed)
    state:SetAttribute("EcosystemHerbivoreBirthsTotal", totals.herbivoreBirths)
    state:SetAttribute("EcosystemHerbivoreDeathsTotal", totals.herbivoreDeaths)
    state:SetAttribute("EcosystemPredatorKillsTotal", totals.predatorKills)
    state:SetAttribute("EcosystemPredatorBirthsTotal", totals.predatorBirths)
    state:SetAttribute("EcosystemPredatorDeathsTotal", totals.predatorDeaths)
    state:SetAttribute("EcosystemCarrionDecomposedTotal", totals.carrionDecomposed)
    state:SetAttribute("EcosystemScavengedTotal", totals.scavenged)
    state:SetAttribute("EcosystemNutrientCreatedTotal", totals.nutrientCreated)
    state:SetAttribute("EcosystemFertilityGainTotal", totals.fertilityGain)
end

local function publishPopulationSummary(state, summary)
    state:SetAttribute("EcosystemHerbivores", summary.herbivores)
    state:SetAttribute("EcosystemPredators", summary.predators)
    state:SetAttribute("EcosystemScavengers", summary.scavengers)
    state:SetAttribute("EcosystemCarrion", summary.carrion)
    state:SetAttribute("EcosystemNutrients", summary.nutrients)
    state:SetAttribute("EcosystemAverageFertility", summary.averageFertility)
    state:SetAttribute("EcosystemMaxDanger", summary.maxEcosystemDanger)
end

function EcosystemService.Start()
    if started then return result end
    started = true

    local bridgeResult = SurvivalBridgeService.Start()
    local runtime = bridgeResult.runtime
    local state = runtime.state
    state:SetAttribute("Version", "W7")
    state:SetAttribute("W7Status", "BOOTING")

    local ecosystem = EcosystemSystem.new(runtime.grid, {
        batchSize = 512,
        referenceStep = runtime.config.fixedStep * 8,
    })
    ecosystem:Initialize(runtime.dirty)
    runtime.ecosystem = ecosystem

    local initialSummary = ecosystem:Recount()
    publishPopulationSummary(state, initialSummary)
    publishTotals(state, ecosystem)
    state:SetAttribute("EcosystemFingerprint", EcosystemSystem.Fingerprint(runtime.grid))

    runtime.clock:RegisterSystem("W7.Ecosystem", 8, function(context)
        local stats = ecosystem:Step(runtime.dirty, runtime.config.fixedStep * 8)
        applyProducerConsumption(runtime, stats)
        publishResourceTotals(state, runtime)
        publishBatch(state, stats)
        publishTotals(state, ecosystem)

        if stats.cycleCompleted then
            local summary = ecosystem:Recount()
            local fingerprint = EcosystemSystem.Fingerprint(runtime.grid)
            state:SetAttribute("EcosystemFingerprint", fingerprint)
            state:SetAttribute("ResourceFingerprint", LivingResourceSystem.Fingerprint(runtime.grid))
            publishPopulationSummary(state, summary)

            runtime.events:Emit("world.ecosystem.cycle", {
                cycle = stats.cycle,
                fingerprint = fingerprint,
                herbivores = summary.herbivores,
                predators = summary.predators,
                scavengers = summary.scavengers,
                carrion = summary.carrion,
                nutrients = summary.nutrients,
                averageFertility = summary.averageFertility,
                maxEcosystemDanger = summary.maxEcosystemDanger,
                foodConsumed = stats.foodConsumed,
                vegetationConsumed = stats.vegetationConsumed,
            }, context.tick)
        end
    end, 800)

    local passed, checks, verifierStats = W7Verifier.Run()
    state:SetAttribute("W7Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W7Check_" .. name, value)
    end
    state:SetAttribute("W7VerifierFingerprint", verifierStats.fingerprint)
    state:SetAttribute("W7VerifierBatchProcessed", verifierStats.batchProcessed)
    state:SetAttribute("W7VerifierFoodConsumed", verifierStats.foodConsumed)
    state:SetAttribute("W7VerifierPredatorKills", verifierStats.predatorKills)
    state:SetAttribute("W7VerifierRecycledFertility", verifierStats.recycledFertility)

    runtime.events:Emit("world.ecosystem.started", {
        batchSize = ecosystem.config.batchSize,
        fingerprint = state:GetAttribute("EcosystemFingerprint"),
        herbivores = initialSummary.herbivores,
        predators = initialSummary.predators,
        scavengers = initialSummary.scavengers,
    }, runtime.clock.tick)

    result = {
        runtime = runtime,
        ecosystem = ecosystem,
        passed = passed,
        checks = checks,
    }
    return result
end

function EcosystemService.GetResult()
    return result
end

function EcosystemService.IsStarted()
    return started
end

return EcosystemService

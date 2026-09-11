local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local FiscalPolicy = require(Kingdom.K11.FiscalPolicy)
local Verifier = require(Kingdom.K11.K11Verifier)

local scope = StateWriter.Scope("K11FiscalPolicy")
scope:SetAttribute("Version", "K11-0.1")
scope:SetAttribute("ExecutionMode", "shadow")
scope:SetAttribute("OwnsTreasury", false)
scope:SetAttribute("OwnsStock", false)

local lastTick = -1
local function run()
    local snapshot = SourceReader.Snapshot()
    local tick = snapshot.cadence.agentTick
    if tick == lastTick then return end
    lastTick = tick

    local beforeStocks = SourceReader.ReadStocks()
    local plan = FiscalPolicy.Plan(snapshot, {})
    local txPlan = FiscalPolicy.TransactionPlan(plan, tick)

    StateWriter.SetMany(scope, {
        LastProcessedTick = tick,
        Decision = plan.decision,
        SuggestedTaxRate = math.floor(plan.taxRate * 10000 + 0.5) / 100,
        EstimatedRevenue = math.floor(plan.estimatedRevenue * 100 + 0.5) / 100,
        Legitimacy = math.floor(plan.legitimacy * 1000 + 0.5) / 10,
        ReliefNeed = math.floor(plan.reliefNeed * 1000 + 0.5) / 10,
        SecurityNeed = math.floor(plan.securityNeed * 1000 + 0.5) / 10,
        InfrastructureNeed = math.floor(plan.infrastructureNeed * 1000 + 0.5) / 10,
        ReliefBudget = math.floor(plan.allocations.relief * 100 + 0.5) / 100,
        SecurityBudget = math.floor(plan.allocations.security * 100 + 0.5) / 100,
        InfrastructureBudget = math.floor(plan.allocations.infrastructure * 100 + 0.5) / 100,
        PlannedTransactionCount = #txPlan,
        ExecutedTransactionCount = 0,
    })

    Verifier.Verify(scope, beforeStocks, SourceReader.ReadStocks(), plan)
end

local state = SourceReader.AgentState()
if state then state:GetAttributeChangedSignal("WorldTick"):Connect(run) end
run()

print("[AstraKingdom] K11 Fiscal Policy attached in shadow mode")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K5Governance = Kingdom:WaitForChild("K5Governance")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local GovernanceAdvisory = require(K5Governance.GovernanceAdvisory)
local K5Verifier = require(K5Governance.K5Verifier)

local scope = StateWriter.Scope("K5Governance")
scope:SetAttribute("Module", "KingdomK5Governance")
scope:SetAttribute("Authority", "advisory-only")
scope:SetAttribute("CadenceSource", "AgentWorldTick")
scope:SetAttribute("OwnsTreasury", false)
scope:SetAttribute("OwnsTaxCollection", false)

local lastTick = -1
local revision = 0
local lastSignature = nil

local function snapshotAgents()
    local result = {}
    local agents = SourceReader.Agents()
    if not agents then return result end
    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then
            local humanoid = agent:FindFirstChildOfClass("Humanoid")
            result[agent.Name] = table.concat({
                tostring(agent:GetAttribute("Role")),
                tostring(agent:GetAttribute("Hunger")),
                tostring(agent:GetAttribute("Thirst")),
                tostring(agent:GetAttribute("Energy")),
                tostring(agent:GetAttribute("Safety")),
                tostring(agent:GetAttribute("Social")),
                tostring(humanoid and humanoid.Health or "nil"),
            }, "|")
        end
    end
    return result
end

local function signature(result)
    return table.concat({
        result.decision,
        tostring(result.legitimacy),
        tostring(result.reliefNeed),
        tostring(result.securityNeed),
        tostring(result.infrastructureNeed),
        tostring(result.suggestedTaxRatePct),
        tostring(result.budgetSecurityPct),
        tostring(result.budgetReliefPct),
        tostring(result.budgetInfrastructurePct),
    }, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local agentsBefore = snapshotAgents()
    local source = SourceReader.Snapshot()
    local result = GovernanceAdvisory.Compute(source)

    local nextSignature = signature(result)
    if nextSignature ~= lastSignature then
        revision += 1
        lastSignature = nextSignature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        Decision = result.decision,
        Legitimacy = result.legitimacy,
        ProsperityProxy = result.prosperityProxy,
        UnrestProxy = result.unrestProxy,
        ReliefNeed = result.reliefNeed,
        SecurityNeed = result.securityNeed,
        InfrastructureNeed = result.infrastructureNeed,
        SuggestedTaxRatePct = result.suggestedTaxRatePct,
        BudgetSecurityPct = result.budgetSecurityPct,
        BudgetReliefPct = result.budgetReliefPct,
        BudgetInfrastructurePct = result.budgetInfrastructurePct,
        BudgetAdministrationPct = result.budgetAdministrationPct,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
    })

    local stocksAfter = SourceReader.ReadStocks()
    local agentsAfter = snapshotAgents()
    K5Verifier.Run(scope, result, stocksBefore, stocksAfter, agentsBefore, agentsAfter)
end

local agentState = SourceReader.AgentState()
if agentState then
    lastTick = agentState:GetAttribute("WorldTick") or 0
    agentState:GetAttributeChangedSignal("WorldTick"):Connect(function()
        local tick = agentState:GetAttribute("WorldTick") or 0
        if tick ~= lastTick then
            lastTick = tick
            publish()
        end
    end)
end

publish()
print("[AstraLife] Kingdom K5 Governance online: advisory-only policy projection")

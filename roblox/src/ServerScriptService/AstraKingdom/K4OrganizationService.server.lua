local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")
local K4Organization = Kingdom:WaitForChild("K4Organization")

local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local OrganizationState = require(K4Organization.OrganizationState)
local K4Verifier = require(K4Organization.K4Verifier)

local scope = StateWriter.Scope("K4Organization")
scope:SetAttribute("Module", "KingdomK4Organization")
scope:SetAttribute("Authority", "aggregate-only")
scope:SetAttribute("CadenceSource", "AgentWorldTick")

local lastTick = -1
local revision = 0
local lastSignature = nil

local function snapshotRoles()
    local roles = {}
    local agents = SourceReader.Agents()
    if not agents then return roles end
    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then roles[agent.Name] = agent:GetAttribute("Role") end
    end
    return roles
end

local function signature(result)
    return table.concat({
        result.state,
        tostring(result.memberCount),
        tostring(result.reserveHealth),
        tostring(result.cohesion),
        tostring(result.operationalCapacity),
        tostring(result.roleCoverage),
        tostring(result.reputation),
    }, "|")
end

local function publish()
    local stocksBefore = SourceReader.ReadStocks()
    local rolesBefore = snapshotRoles()
    local source = SourceReader.Snapshot()
    local result = OrganizationState.Compute(source, SourceReader.Agents())

    local nextSignature = signature(result)
    if nextSignature ~= lastSignature then
        revision += 1
        lastSignature = nextSignature
    end

    StateWriter.SetMany(scope, {
        SchemaVersion = result.schemaVersion,
        OrganizationId = result.organizationId,
        State = result.state,
        MemberCount = result.memberCount,
        ReservePerMember = result.reservePerMember,
        ReserveHealth = result.reserveHealth,
        Infrastructure = result.infrastructure,
        Cohesion = result.cohesion,
        OperationalCapacity = result.operationalCapacity,
        RoleCoverage = result.roleCoverage,
        Reputation = result.reputation,
        Revision = revision,
        ObservedAgentTick = source.cadence.agentTick,
        ObservedLivingWorldTick = source.cadence.livingWorldTick,
    })

    for role, count in pairs(result.roleCounts) do
        StateWriter.Set(scope, "Role_" .. role, count)
    end

    local stocksAfter = SourceReader.ReadStocks()
    local rolesAfter = snapshotRoles()
    K4Verifier.Run(scope, result, stocksBefore, stocksAfter, rolesBefore, rolesAfter)
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
print("[AstraLife] Kingdom K4 Organization online: aggregate projection only")

-- I0.3 Runtime IntegrationVerifier: derives the composed-system status from
-- live evidence on the living-world and colony state instances. Pure logic:
-- reads attributes only, never writes them, and requires nothing.

local IntegrationVerifier = {}
IntegrationVerifier.__index = IntegrationVerifier

local WORLD_STATUS_ATTRIBUTES = {
    "W0Status", "W1Status", "W2Status", "W3Status",
    "W4Status", "W5Status", "W6Status", "W7Status",
}

local STEP_ATTRIBUTES = { "HydrologySteps", "ResourceSteps", "HazardSteps", "EcosystemSteps" }

local REQUIRED_FOR_PASS = {
    "LivingWorldAdvancing",
    "ColonyWorldTickAdvancing",
    "HydrologyStepsActive",
    "ResourceStepsActive",
    "HazardStepsActive",
    "EcosystemStepsActive",
    "AgentsOnline",
    "W6BridgeReady",
    "CommunicationBounded",
    "NoInboxDrops",
    "NoRuntimeError",
    "ScaleHealthy",
    "StuckHealthy",
    "W6TransactionObserved",
}

local function countWorldFails(livingState)
    local fails = 0
    for _, name in ipairs(WORLD_STATUS_ATTRIBUTES) do
        if livingState:GetAttribute(name) == "FAIL" then fails += 1 end
    end
    return fails
end

-- One living-world system per attribute: "XSteps" -> "XStepsActive" evidence.
local function sampleStepActivity(evidence, livingState)
    for _, name in ipairs(STEP_ATTRIBUTES) do
        local value = livingState:GetAttribute(name) or 0
        evidence[name .. "Active"] = value > 0
        evidence[name .. "Active_Value"] = value
    end
end

local function sampleColony(evidence, foldersState, config)
    local online = foldersState:GetAttribute("ScaleOnlineAgents") or 0
    evidence.AgentsOnline = online >= (config.ScaleAgentCount or 0)
    evidence.AgentsOnline_Value = online

    local registry = foldersState:GetAttribute("ScaleMessageRegistry") or 0
    evidence.CommunicationBounded = registry <= (config.ScaleMaxMessageRegistry or 0)
    evidence.CommunicationBounded_Value = registry

    local dropped = foldersState:GetAttribute("ScaleDroppedMessages") or 0
    evidence.NoInboxDrops = dropped == 0
    evidence.NoInboxDrops_Value = dropped

    evidence.NoRuntimeError = foldersState:GetAttribute("ScaleRuntimeError") ~= true
    evidence.ScaleHealthy = foldersState:GetAttribute("Scale12Status") == "PASS"

    local stuck = foldersState:GetAttribute("ScaleStuckAgents") or 0
    evidence.StuckHealthy = stuck <= (config.ScaleMaxStuckAgents or 0)
    evidence.StuckHealthy_Value = stuck
end

-- W6 transactions are only required once the soak grace window has elapsed.
local function sampleBridge(evidence, livingState, config, nowLivingTick)
    local committed = livingState:GetAttribute("W6TransactionsCommitted") or 0
    local graceActive = nowLivingTick < (config.IntegrationTransactionGraceTicks or 0)
    evidence.W6TransactionObserved = graceActive or committed > 0
    evidence.W6TransactionGraceActive = graceActive
    evidence.W6TransactionObserved_Value = committed
end

function IntegrationVerifier.new()
    return setmetatable({
        _prevLivingTick = nil,
        _prevColonyTick = nil,
        _advancedOnce = false,
        _lastEvidence = nil,
    }, IntegrationVerifier)
end

function IntegrationVerifier:Reset()
    self._prevLivingTick = nil
    self._prevColonyTick = nil
    self._advancedOnce = false
    self._lastEvidence = nil
end

function IntegrationVerifier:GetEvidence()
    return self._lastEvidence
end

function IntegrationVerifier:Update(livingState, foldersState, config, nowLivingTick)
    local evidence = {}
    nowLivingTick = nowLivingTick or livingState:GetAttribute("LivingWorldTick") or 0
    local colonyTick = foldersState:GetAttribute("WorldTick") or 0

    -- First call ever: deltas are unknown, so advancement is false but not a failure.
    local livingDelta = nil
    if self._prevLivingTick ~= nil then
        livingDelta = math.max(0, nowLivingTick - self._prevLivingTick)
    end
    local colonyDelta = nil
    if self._prevColonyTick ~= nil then
        colonyDelta = math.max(0, colonyTick - self._prevColonyTick)
    end

    local livingAdvancing = livingDelta ~= nil and livingDelta > 0
    local colonyAdvancing = colonyDelta ~= nil and colonyDelta > 0
    if livingAdvancing or colonyAdvancing then self._advancedOnce = true end

    evidence.LivingWorldAdvancing = livingAdvancing
    evidence.ColonyWorldTickAdvancing = colonyAdvancing
    if livingDelta ~= nil then evidence.LivingWorldAdvancing_Value = livingDelta end
    if colonyDelta ~= nil then evidence.ColonyWorldTickAdvancing_Value = colonyDelta end

    sampleStepActivity(evidence, livingState)
    evidence.W6BridgeReady = livingState:GetAttribute("W6BrainIntegrated") == true

    sampleColony(evidence, foldersState, config)
    sampleBridge(evidence, livingState, config, nowLivingTick)

    local hardError = foldersState:GetAttribute("ScaleRuntimeError") == true
        or countWorldFails(livingState) > 0

    local allRequired = true
    for _, name in ipairs(REQUIRED_FOR_PASS) do
        if evidence[name] ~= true then
            allRequired = false
            break
        end
    end

    local status
    if hardError then
        status = "ERROR"
    elseif allRequired then
        status = "PASS"
    elseif not self._advancedOnce then
        status = "BOOTING"
    else
        status = "RUNNING"
    end

    self._prevLivingTick = nowLivingTick
    self._prevColonyTick = colonyTick
    self._lastEvidence = evidence

    return status, evidence
end

return IntegrationVerifier

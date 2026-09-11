local Communication = require(script.Parent.Communication)

local ScaleVerifier = {}

local peakRegistry = 0
local peakInbox = 0
local peakStuck = 0
local historicalBreach = false

local function countAgents(folders, config)
    local total = 0
    local online = 0
    local stuck = 0
    local dropped = 0
    local phases = {}

    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            total += 1
            if agent:GetAttribute("State") == "Online" then online += 1 end
            if (agent:GetAttribute("StuckTicks") or 0) >= config.StuckTicksBeforePath * 2 then stuck += 1 end
            dropped += agent:GetAttribute("DroppedInboxMessages") or 0
            local phase = agent:GetAttribute("DecisionPhaseSeconds")
            if phase ~= nil then phases[string.format("%.2f", phase)] = true end
        end
    end

    local phaseCount = 0
    for _ in pairs(phases) do phaseCount += 1 end
    return total, online, stuck, dropped, phaseCount
end

local function resourceCount(folders)
    local count = 0
    for _, resource in ipairs(folders.resources:GetChildren()) do
        if resource:IsA("BasePart") then count += 1 end
    end
    return count
end

function ScaleVerifier.Update(folders, tick, config)
    local state = folders.state
    local total, online, stuck, dropped, phaseCount = countAgents(folders, config)
    local resources = resourceCount(folders)
    local registry = Communication.RegistrySize()
    local inbox = Communication.TotalInboxSize()

    peakRegistry = math.max(peakRegistry, registry)
    peakInbox = math.max(peakInbox, inbox)
    peakStuck = math.max(peakStuck, stuck)

    state:SetAttribute("ScaleAgentCount", total)
    state:SetAttribute("ScaleOnlineAgents", online)
    state:SetAttribute("ScaleResourceCount", resources)
    state:SetAttribute("ScaleStuckAgents", stuck)
    state:SetAttribute("ScaleDroppedMessages", dropped)
    state:SetAttribute("ScaleDecisionPhaseCount", phaseCount)
    state:SetAttribute("ScaleMessageRegistry", registry)
    state:SetAttribute("ScaleInboxTotal", inbox)
    state:SetAttribute("ScalePeakMessageRegistry", peakRegistry)
    state:SetAttribute("ScalePeakInbox", peakInbox)
    state:SetAttribute("ScalePeakStuckAgents", peakStuck)

    local agentReady = total == config.ScaleAgentCount and online == config.ScaleAgentCount
    local resourceReady = resources >= config.ScaleResourceNodeCount
    local spreadReady = phaseCount == config.ScaleAgentCount
    local roleHealthy = state:GetAttribute("ScaleRoleTargetHealthy") == true
    local queuesHealthy = registry <= config.ScaleMaxMessageRegistry
        and inbox <= config.ScaleAgentCount * config.MaxMessageQueueSize
        and dropped == 0
    local movementHealthy = stuck <= config.ScaleMaxStuckAgents

    state:SetAttribute("ScaleAgentsReady", agentReady)
    state:SetAttribute("ScaleResourcesReady", resourceReady)
    state:SetAttribute("ScaleDecisionSpreadReady", spreadReady)
    state:SetAttribute("ScaleQueuesHealthy", queuesHealthy)
    state:SetAttribute("ScaleMovementHealthy", movementHealthy)

    if not queuesHealthy or not movementHealthy then historicalBreach = true end
    state:SetAttribute("ScaleHistoricalBreach", historicalBreach)

    local pass = tick >= config.ScaleVerifierMinTicks
        and agentReady
        and resourceReady
        and spreadReady
        and roleHealthy
        and queuesHealthy
        and movementHealthy

    state:SetAttribute("Scale12Status", pass and "PASS" or "RUNNING")

    if tick >= config.ScaleLongRunTicks then
        state:SetAttribute("Scale12LongRunStatus", (pass and not historicalBreach) and "PASS" or "FAIL")
    else
        state:SetAttribute("Scale12LongRunStatus", "RUNNING")
    end

    return pass
end

return ScaleVerifier

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Core = ReplicatedStorage.Astra.SurvivalCrafting.Core
local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local S0Verifier = require(Core.S0Verifier)

local root = StateWriter.Root()
local scope = StateWriter.Scope("S0Core")
local lastAgentTick, lastLivingTick = -1, -1

local function refresh()
    local before = S0Verifier.Capture(SourceReader)
    local snapshot = SourceReader.Snapshot()
    StateWriter.SetMany(scope, {
        Version = "S0-1",
        AgentTick = snapshot.cadence.agentTick,
        LivingWorldTick = snapshot.cadence.livingWorldTick,
        LivingWorldVersion = snapshot.cadence.livingWorldVersion,
        AgentCount = snapshot.agentCount,
        StructureCount = snapshot.structureCount,
        W6Ready = snapshot.integration.w6Ready,
        W7Ready = snapshot.integration.w7Ready,
        WorldTransactionsOwnedExternally = true,
        NavigationOwnedExternally = true,
    })
    local after = S0Verifier.Capture(SourceReader)
    S0Verifier.Verify(root, before, after)
end

RunService.Heartbeat:Connect(function()
    local cadence = SourceReader.ReadCadence()
    if cadence.agentTick ~= lastAgentTick or cadence.livingWorldTick ~= lastLivingTick then
        lastAgentTick = cadence.agentTick
        lastLivingTick = cadence.livingWorldTick
        refresh()
    end
end)

refresh()

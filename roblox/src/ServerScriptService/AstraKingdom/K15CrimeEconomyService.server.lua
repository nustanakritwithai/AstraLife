local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kingdom = ReplicatedStorage.Astra.Kingdom
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local CrimeEconomy = require(Kingdom.K15.CrimeEconomy)
local K15Verifier = require(Kingdom.K15.K15Verifier)

local scope = StateWriter.Scope("K15CrimeEconomy")
local lastTick = -1

local function step()
    local cadence = SourceReader.ReadCadence()
    if cadence.agentTick == lastTick then return end
    lastTick = cadence.agentTick

    local before = K15Verifier.Capture(SourceReader)
    local values = CrimeEconomy.Evaluate(SourceReader.Snapshot(), StateWriter.Root())
    values.SourceWorldTick = cadence.agentTick
    values.Version = "K15-1"
    values.OwnsCombat = false
    values.OwnsBanditAgents = false
    values.OwnsWorldRoutes = false
    StateWriter.SetMany(scope, values)
    local after = K15Verifier.Capture(SourceReader)
    K15Verifier.Verify(scope, before, after)
end

RunService.Heartbeat:Connect(step)
step()

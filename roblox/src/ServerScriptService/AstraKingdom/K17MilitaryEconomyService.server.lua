local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kingdom = ReplicatedStorage.Astra.Kingdom
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local MilitaryEconomy = require(Kingdom.K17.MilitaryEconomy)
local K17Verifier = require(Kingdom.K17.K17Verifier)

local scope = StateWriter.Scope("K17MilitaryEconomy")
local lastTick = -1

local function step()
    local cadence = SourceReader.ReadCadence()
    if cadence.agentTick == lastTick then return end
    lastTick = cadence.agentTick
    local before = K17Verifier.Capture(SourceReader)
    local values = MilitaryEconomy.Evaluate(SourceReader.Snapshot(), StateWriter.Root())
    values.SourceWorldTick = cadence.agentTick
    values.Version = "K17-1"
    values.OwnsArmy = false
    values.OwnsRecruitment = false
    values.OwnsCombat = false
    values.OwnsSupplyTransactions = false
    StateWriter.SetMany(scope, values)
    K17Verifier.Verify(scope, before, K17Verifier.Capture(SourceReader))
end

RunService.Heartbeat:Connect(step)
step()

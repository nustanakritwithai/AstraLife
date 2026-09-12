local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SurvivalCrafting = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("SurvivalCrafting")
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local CraftingRuntime = require(SurvivalCrafting.Adapter.CraftingRuntime)
local I4Verifier = require(SurvivalCrafting.Adapter.I4Verifier)

-- I4 composition: production crafting chain with atomic commit.
-- S4 → S5 → S6 → S7 → S10 → S4; S8 availability gate only.
-- Emits CraftCompleted outcomes for P7 (never for queue/running ticks).
local scope = StateWriter.Scope("I4CraftingRuntime")
scope:SetAttribute("Version", "I4-1")
scope:SetAttribute("OwnsWorldResources", false)
scope:SetAttribute("OwnsLegacyInventory", false)
scope:SetAttribute("OwnsP7Xp", false)
scope:SetAttribute("RequiresExternalCommitAdapter", false)
scope:SetAttribute("OutcomeEventName", CraftingRuntime.OutcomeEventName)
scope:SetAttribute("Chain", "S4→S5→S6→S7→S10→S4")

local parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService

local existingApi = parent:FindFirstChild("I4CraftingRuntimeApi")
if existingApi then
	existingApi:Destroy()
end
local existingEvent = parent:FindFirstChild("I4CraftOutcomeEvent")
if existingEvent then
	existingEvent:Destroy()
end

-- Runtime used by the live Bindable API (separate from verifier's fresh instances).
local runtime = CraftingRuntime.new({ maxJobs = 32 })

local outcomeEvent = Instance.new("BindableEvent")
outcomeEvent.Name = "I4CraftOutcomeEvent"
outcomeEvent.Parent = parent
runtime:OnOutcome(function(outcome)
	outcomeEvent:Fire(outcome)
end)

local api = Instance.new("BindableFunction")
api.Name = "I4CraftingRuntimeApi"
api.Parent = parent
api.OnInvoke = function(action, payload)
	payload = payload or {}
	if action == "Quote" then
		return runtime:Quote(payload)
	end
	if action == "Start" then
		return runtime:Start(payload, payload.transactionId)
	end
	if action == "Step" then
		return runtime:Step(payload.tick, payload.workUnits)
	end
	if action == "TryCommit" then
		return runtime:TryCommit(payload.jobId)
	end
	if action == "FlushPendingCommits" then
		return runtime:FlushPendingCommits()
	end
	if action == "SnapshotJob" then
		return runtime:SnapshotJob(payload.jobId)
	end
	if action == "BindStationContainer" then
		return runtime:BindStationContainer(payload.stationKey, payload.profileId)
	end
	if action == "GetContainerSnapshot" then
		local container = runtime:GetContainer(payload.stationKey)
		if not container then
			return nil, "unknown_container"
		end
		return container:Snapshot()
	end
	if action == "ContainerAdd" then
		local container = runtime:GetContainer(payload.stationKey)
		if not container then
			return nil, "unknown_container"
		end
		return container:Add(payload.bayName, payload.item, payload.transactionId)
	end
	if action == "GetOutcomes" then
		return runtime:GetOutcomes()
	end
	if action == "GetResearchSnapshot" then
		return runtime:GetResearch():Snapshot(payload.profileId or "default")
	end
	if action == "ResearchQuote" then
		return runtime:GetResearch():Quote(payload.profileId or "default", payload.nodeId)
	end
	if action == "ResearchCommit" then
		return runtime:GetResearch():Commit(
			payload.profileId or "default",
			payload.nodeId,
			payload.transactionId,
			payload.paymentReceipt
		)
	end
	if action == "OutcomeEventName" then
		return CraftingRuntime.OutcomeEventName
	end
	return nil, "unknown_action"
end

I4Verifier.Verify(CraftingRuntime, scope)

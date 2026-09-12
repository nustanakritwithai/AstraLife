-- I6 composition: profession adapter + P7 outcome sink.
-- Gatherer → S2/S3 quotes on W6 harvest; Builder → B1 place/repair; P7 XP on outcomes only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local SurvivalCrafting = Astra:WaitForChild("SurvivalCrafting")
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local Contract = require(SurvivalCrafting.Core.Contract)
local ProfessionAdapter = require(SurvivalCrafting.Adapter.ProfessionAdapter)
local P7OutcomeSink = require(SurvivalCrafting.Adapter.P7OutcomeSink)
local I6Verifier = require(SurvivalCrafting.Adapter.I6Verifier)
local SkillLearning = require(Astra.SkillLearning)
local Config = require(Astra.Config)

local function waitUntil(predicate, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 60)
	while os.clock() < deadline do
		local ok, value = pcall(predicate)
		if ok and value then
			return value
		end
		task.wait(0.25)
	end
	local ok, value = pcall(predicate)
	return ok and value or nil
end

local parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService

waitUntil(function()
	local root = Workspace:FindFirstChild(Contract.StateRootName)
	return root ~= nil
end, 60)

-- Best-effort: allow prior I-phase verifiers to publish.
waitUntil(function()
	local root = Workspace:FindFirstChild(Contract.StateRootName)
	if not root then
		return false
	end
	local i3 = root:FindFirstChild("I3InventoryShadow")
	local i4 = root:FindFirstChild("I4CraftingRuntime")
	local i5 = root:FindFirstChild("I5BuildingCompose")
	return i3 and i3:GetAttribute("I3Status") ~= nil
		and i4 and i4:GetAttribute("I4Status") ~= nil
		and i5 and i5:GetAttribute("I5Status") ~= nil
end, 45)

local agentsFolder = Workspace:FindFirstChild("AstraAgents")
local stateFolder = Workspace:FindFirstChild("AstraWorldState")
	or Workspace:FindFirstChild("AstraState")
	or Workspace:FindFirstChild("AstraColonyState")

-- Resolve colony state folder used by AgentService (AstraWorldState attrs).
if not stateFolder then
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Folder") and child:GetAttribute("WorldTick") ~= nil then
			stateFolder = child
			break
		end
	end
end

local function findAgent(actorId)
	if not agentsFolder or type(actorId) ~= "string" then
		return nil
	end
	return agentsFolder:FindFirstChild(actorId)
end

if stateFolder then
	stateFolder:SetAttribute("P7_I6OutcomeOnly", true)
	stateFolder:SetAttribute("I6_ProfessionComposeStarted", true)
end

local sink = P7OutcomeSink.new({
	grantFn = function(actorId, skill, amount, category, eventId, _meta)
		local agent = findAgent(actorId)
		if not agent then
			return 0
		end
		local tick = 0
		if stateFolder then
			tick = stateFolder:GetAttribute("WorldTick") or 0
			stateFolder:SetAttribute("P7_I6OutcomeOnly", true)
			stateFolder:SetAttribute("P7_I6OutcomeObserved", true)
		end
		return SkillLearning.GrantOutcome(
			agent,
			skill,
			amount,
			category,
			eventId,
			tick,
			Config,
			stateFolder
		)
	end,
})

local scope = StateWriter.Scope("I6ProfessionIntegration")
scope:SetAttribute("Version", ProfessionAdapter.Version)
scope:SetAttribute("I6ProfessionMode", ProfessionAdapter.ProfessionMode)
scope:SetAttribute("OwnsRoleSkillGoal", false)
scope:SetAttribute("OwnsWorldResources", false)
scope:SetAttribute("BuildingAuthority", "B1-preferred+P3-fallback")
scope:SetAttribute("I6DualBuildingTruth", true)
scope:SetAttribute("GatherPolicy", "S2+S3-quote")
scope:SetAttribute("P7XpMode", "outcome-events-only")

-- Live Bindable API for brains / bridge.
local existingApi = parent:FindFirstChild("I6ProfessionApi")
if existingApi then
	existingApi:Destroy()
end
local existingOutcome = parent:FindFirstChild("I6ProfessionOutcomeEvent")
if existingOutcome then
	existingOutcome:Destroy()
end

local outcomeEvent = Instance.new("BindableEvent")
outcomeEvent.Name = "I6ProfessionOutcomeEvent"
outcomeEvent.Parent = parent

local function publishOutcome(raw)
	local result = sink:Ingest(raw)
	if result and result.ok and not result.duplicate then
		outcomeEvent:Fire(result)
	end
	scope:SetAttribute("I6LiveGranted", sink:GetStats().granted)
	scope:SetAttribute("I6LiveDuplicates", sink:GetStats().duplicates)
	scope:SetAttribute("I6LiveRejected", sink:GetStats().rejected)
	return result
end

local api = Instance.new("BindableFunction")
api.Name = "I6ProfessionApi"
api.Parent = parent
api.OnInvoke = function(action, payload)
	payload = payload or {}
	if action == "AllowedActions" then
		return ProfessionAdapter.AllowedActions(payload.role)
	end
	if action == "IsActionAllowed" then
		return ProfessionAdapter.IsActionAllowed(payload.role, payload.action)
	end
	if action == "QuoteGather" then
		return ProfessionAdapter.QuoteGather(payload.worldResourceType, payload.actorId, payload)
	end
	if action == "HarvestContext" then
		return ProfessionAdapter.HarvestContext(payload.worldResourceType, payload.actorId, payload)
	end
	if action == "ListPlaceableBuildParts" then
		return ProfessionAdapter.ListPlaceableBuildParts(payload.actorId)
	end
	if action == "PickPlaceableBuildPart" then
		return ProfessionAdapter.PickPlaceableBuildPart(payload.actorId)
	end
	if action == "IngestOutcome" then
		return publishOutcome(payload)
	end
	if action == "GetSinkStats" then
		return sink:GetStats()
	end
	if action == "ProfessionMode" then
		return ProfessionAdapter.ProfessionMode
	end
	return nil, "unknown_action"
end

-- Wire I4 CraftCompleted → P7 outcome sink (never Start/Step).
task.defer(function()
	local craftEvent = parent:WaitForChild("I4CraftOutcomeEvent", 60)
	if craftEvent and craftEvent:IsA("BindableEvent") then
		craftEvent.Event:Connect(function(outcome)
			local normalized = P7OutcomeSink.FromCraftCompleted(outcome)
			if normalized then
				publishOutcome(normalized)
			end
		end)
		scope:SetAttribute("I6WiredI4CraftOutcome", true)
	else
		scope:SetAttribute("I6WiredI4CraftOutcome", false)
	end
end)

-- Wire StationProcessingCompleted the same way (I4 station-hosted commits; same tx → dedupe).
task.defer(function()
	local stationEvent = parent:WaitForChild("I4StationOutcomeEvent", 60)
	if stationEvent and stationEvent:IsA("BindableEvent") then
		stationEvent.Event:Connect(function(outcome)
			local normalized = P7OutcomeSink.FromStationProcessingCompleted(outcome)
			if normalized then
				publishOutcome(normalized)
			end
		end)
		scope:SetAttribute("I6WiredStationOutcome", true)
	else
		-- Documented: station commits still arrive via CraftCompleted; dedicated event preferred.
		scope:SetAttribute("I6WiredStationOutcome", false)
		scope:SetAttribute("I6StationOutcomeSkipReason", "no_I4StationOutcomeEvent")
	end
end)

-- Wire B1 building events when WorldService event bus is available.
task.defer(function()
	local buildingFolder = ServerScriptService:FindFirstChild("AstraBuilding")
	if not buildingFolder then
		return
	end
	local ok, BuildingLifecycleService = pcall(function()
		return require(buildingFolder:WaitForChild("BuildingLifecycleService", 30))
	end)
	if not ok or not BuildingLifecycleService then
		return
	end
	local result = BuildingLifecycleService.GetResult and BuildingLifecycleService.GetResult()
	local runtime = result and result.runtime
	local events = runtime and runtime.events
	if not events or not events.Subscribe then
		scope:SetAttribute("I6WiredB1Events", false)
		return
	end

	local function onBuildingEvent(event)
		local payload = event and event.payload or {}
		local topic = event and event.topic
		local kind = nil
		local eventName = nil
		if topic == "building.piece.placed" then
			kind = "building_placed"
			eventName = "BuildingPlaced"
		elseif topic == "building.piece.repaired" then
			kind = "building_repaired"
			eventName = "BuildingRepaired"
		elseif topic == "building.piece.demolished" then
			kind = "building_demolished"
			eventName = "BuildingDemolished"
		else
			return
		end
		local transactionId = payload.transactionId
		-- Ignore ModularBuilding place emits without transactionId (I6 PlaceRoot re-emits with one).
		if type(transactionId) ~= "string" or transactionId == "" then
			if topic == "building.piece.placed" then
				return
			end
			transactionId = string.format("b1:%s:%s", tostring(topic), tostring(payload.pieceId or "unknown"))
		end
		publishOutcome({
			eventName = eventName,
			kind = kind,
			transactionId = transactionId,
			actorId = payload.actorId or (payload.metadata and payload.metadata.actorId),
			pieceId = payload.pieceId,
		})
	end

	events:Subscribe("building.piece.placed", onBuildingEvent)
	events:Subscribe("building.piece.repaired", onBuildingEvent)
	events:Subscribe("building.piece.demolished", onBuildingEvent)
	scope:SetAttribute("I6WiredB1Events", true)
end)

local passed, errors, stats = I6Verifier.Verify({
	ProfessionAdapter = ProfessionAdapter,
	P7OutcomeSink = P7OutcomeSink,
}, scope)

print(string.format(
	"[AstraLife][I6] compose status=%s mode=%s errors=%d",
	tostring(scope:GetAttribute("I6Status")),
	tostring(scope:GetAttribute("I6ProfessionMode")),
	tonumber(stats and stats.errorCount) or #(errors or {})
))
if not passed then
	warn("[AstraLife][I6] compose errors:", table.concat(errors or {}, ","))
end

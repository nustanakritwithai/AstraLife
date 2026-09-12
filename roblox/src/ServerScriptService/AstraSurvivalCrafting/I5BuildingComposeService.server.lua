-- I5 composition bootstrap: waits for B1 building runtime + S12 quote scope,
-- then runs I5Verifier into the SurvivalCrafting composition root.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local SurvivalCrafting = Astra:WaitForChild("SurvivalCrafting")
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local Contract = require(SurvivalCrafting.Core.Contract)
local I5Verifier = require(SurvivalCrafting.Adapter.I5Verifier)

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

local buildingFolder = ServerScriptService:WaitForChild("AstraBuilding", 60)
local BuildingLifecycleService = require(buildingFolder:WaitForChild("BuildingLifecycleService"))

-- Ensure B0/B1 modules start (idempotent with bootstraps).
BuildingLifecycleService.Start()

waitUntil(function()
	local state = Workspace:FindFirstChild("AstraBuildingState")
	return state
		and state:GetAttribute("B0Status") ~= nil
		and state:GetAttribute("B1Status") ~= nil
		and state:GetAttribute("B1HardeningStatus") ~= nil
		and state
end, 60)

waitUntil(function()
	local root = Workspace:FindFirstChild(Contract.StateRootName)
	return root and root:FindFirstChild("S12Durability")
end, 60)

-- Best-effort: allow I3/I4 verifiers to publish before non-regression checks.
waitUntil(function()
	local root = Workspace:FindFirstChild(Contract.StateRootName)
	if not root then return false end
	local i3 = root:FindFirstChild("I3InventoryShadow")
	local i4 = root:FindFirstChild("I4CraftingRuntime")
	return i3 and i3:GetAttribute("I3Status") ~= nil
		and i4 and i4:GetAttribute("I4Status") ~= nil
end, 30)

local scope = StateWriter.Scope("I5BuildingCompose")
scope:SetAttribute("Version", "I5-1")
scope:SetAttribute("OwnsStructureHealth", false)
scope:SetAttribute("BuildingAuthority", "B1")
scope:SetAttribute("SurfaceResolver", "Astra.World.SurfaceResolver")

local passed, errors, stats = I5Verifier.Verify(BuildingLifecycleService, scope)

print(string.format(
	"[AstraLife][I5] compose status=%s errors=%d mapping=%s",
	tostring(scope:GetAttribute("I5Status")),
	tonumber(stats and stats.errorCount) or #(errors or {}),
	tostring(scope:GetAttribute("I5MappingCount"))
))
if not passed then
	warn("[AstraLife][I5] compose errors:", table.concat(errors or {}, ","))
end

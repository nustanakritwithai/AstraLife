local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local StateWriter = require(Astra.SurvivalCrafting.Core.StateWriter)
local Contract = require(Astra.SurvivalCrafting.Core.Contract)

-- I1 composition aggregator: rolls the per-phase SxStatus values up into one
-- SCompositionStatus without owning any S state itself. Phases own their own
-- scopes; this only reads them.
local SCOPE_BY_PHASE = {
	S1 = "S1Items",
	S2 = "S2Gathering",
	S3 = "S3Tools",
	S4 = "S4InventoryV2",
	S5 = "S5RecipeGraph",
	S6 = "S6CraftQueue",
	S7 = "S7Stations",
	S8 = "S8Research",
	S10 = "S10Containers",
	S11 = "S11Automation",
	S12 = "S12Durability",
	I2 = "I2WorldItemAdapter",
	I3 = "I3InventoryShadow",
	I4 = "I4CraftingRuntime",
}

-- S0 reports on the root itself; every other phase owns one scope.
local REQUIRED_PASS_COUNT = 1
for _ in pairs(SCOPE_BY_PHASE) do
	REQUIRED_PASS_COUNT += 1
end

local COMPOSITION_TIMEOUT_SECONDS = 30
local startedAt = os.clock()

local function compositionRoot()
	return Workspace:FindFirstChild(Contract.StateRootName)
end

local function collectStatuses(root)
	local statuses = {}
	statuses.S0 = root:GetAttribute("S0Status")
	for phase, scopeName in pairs(SCOPE_BY_PHASE) do
		local scope = root:FindFirstChild(scopeName)
		statuses[phase] = scope and scope:GetAttribute(phase .. "Status") or nil
	end
	return statuses
end

while not compositionRoot() do
	task.wait(0.5)
end

while true do
	local root = compositionRoot()
	local statuses = collectStatuses(root)

	local failing = {}
	local pending = {}
	local passCount = 0
	for phase, status in pairs(statuses) do
		if status == "PASS" then
			passCount += 1
		elseif status == "FAIL" or status == "ERROR" then
			-- I3: verifier ERROR must fail composition immediately (not sit in pending).
			table.insert(failing, phase)
		else
			table.insert(pending, phase)
		end
	end

	local status = "RUNNING"
	if #failing > 0 then
		status = "FAIL"
		table.sort(failing)
	elseif passCount == REQUIRED_PASS_COUNT then
		status = "PASS"
	elseif #pending > 0 and os.clock() - startedAt > COMPOSITION_TIMEOUT_SECONDS then
		status = "FAIL"
		table.sort(pending)
		failing = pending
		root:SetAttribute("SCompositionTimeout", true)
	end

	root:SetAttribute("SCompositionStatus", status)
	root:SetAttribute("SCompositionFailing", table.concat(failing, ","))
	root:SetAttribute("SCompositionPassCount", passCount)

	if status == "PASS" or status == "FAIL" then break end
	task.wait(1)
end

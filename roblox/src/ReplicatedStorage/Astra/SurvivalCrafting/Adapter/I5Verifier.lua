-- I5 compose verifier: B1 status, shared SurfaceResolver placement, W5 Build gate,
-- single health authority (S12 quote-only / B1 ApplyDamage), transaction dedupe,
-- and I3/I4 non-regression on the SurvivalCrafting composition root.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local BuildingModules = Astra:WaitForChild("Building")
local WorldModules = Astra:WaitForChild("World")
local SurvivalCrafting = Astra:WaitForChild("SurvivalCrafting")
local Contract = require(SurvivalCrafting.Core.Contract)
local SurfaceResolver = require(WorldModules.SurfaceResolver)
local SurfaceResolverContract = require(WorldModules.SurfaceResolverContract)
local CraftedBuildPartMapping = require(BuildingModules.CraftedBuildPartMapping)
local S12B1DamageBridge = require(BuildingModules.S12B1DamageBridge)
local DurabilityPolicy = require(SurvivalCrafting.S12.DurabilityPolicy)
local BuildPieceCatalog = require(BuildingModules.BuildPieceCatalog)
local B1HardeningVerifier = require(BuildingModules.B1HardeningVerifier)

local I5Verifier = {}

local function addError(errors, name)
	table.insert(errors, name)
end

local function survivalRoot()
	return Workspace:FindFirstChild(Contract.StateRootName)
end

local function scopeStatus(root, scopeName, attr)
	local scope = root and root:FindFirstChild(scopeName)
	return scope and scope:GetAttribute(attr) or nil
end

function I5Verifier.Verify(BuildingLifecycleService, scope)
	local errors = {}

	local buildingState = Workspace:FindFirstChild("AstraBuildingState")
	if not buildingState then
		addError(errors, "missing_building_state")
	else
		if buildingState:GetAttribute("B0Status") ~= "PASS" then
			addError(errors, "b0_status")
		end
		if buildingState:GetAttribute("B1Status") ~= "PASS" then
			addError(errors, "b1_status")
		end
		if buildingState:GetAttribute("B1HardeningStatus") ~= "PASS" then
			addError(errors, "b1_hardening_status")
		end
	end

	local surfacePassed, surfaceChecks = SurfaceResolverContract.Run()
	if not surfacePassed then
		addError(errors, "shared_surface_resolver_contract")
	end
	if surfaceChecks and surfaceChecks.preservesXZ ~= true then
		addError(errors, "surface_preserves_xz")
	end
	if surfaceChecks and surfaceChecks.excludeRebuilt ~= true then
		addError(errors, "surface_exclude_rebuilt")
	end

	-- Placement must go through shared World SurfaceResolver (no Building-private math).
	-- Probe PreviewRoot when lifecycle is available.
	if BuildingLifecycleService and BuildingLifecycleService.PreviewRoot then
		local preview = BuildingLifecycleService.PreviewRoot(
			"FoundationSquare",
			Vector3.new(0, 50, 0),
			0
		)
		if type(preview) ~= "table" then
			addError(errors, "preview_root_missing")
		else
			-- W5 Build gate is enforced inside PlacementValidator via environmentQuery.
			-- Allowed may be false on wet/steep cells; reason must be from the gate or ok path.
			if preview.allowed == true then
				if typeof(preview.cframe) ~= "CFrame" then
					addError(errors, "preview_cframe")
				elseif preview.surfaceY ~= nil then
					local projected = SurfaceResolver.TopY(Vector3.new(preview.cframe.Position.X, 0, preview.cframe.Position.Z), {})
					if math.abs((preview.surfaceY or 0) - projected) > 1e-2 then
						addError(errors, "preview_uses_shared_resolver")
					end
				end
			elseif preview.reason == nil then
				addError(errors, "preview_reason_missing")
			end
		end
	else
		addError(errors, "lifecycle_preview_unavailable")
	end

	-- Mapping coverage for known S1 build parts.
	if CraftedBuildPartMapping.Count() < 7 then
		addError(errors, "crafted_mapping_incomplete")
	end
	local woodFoundation = CraftedBuildPartMapping.Get("WoodFoundation")
	if not woodFoundation
		or woodFoundation.pieceType ~= "FoundationSquare"
		or woodFoundation.materialGrade ~= "Wood"
		or not BuildPieceCatalog.Get(woodFoundation.pieceType)
	then
		addError(errors, "crafted_mapping_wood_foundation")
	end

	-- S12 quote → B1 ApplyDamage boundary (no second health store).
	local root = survivalRoot()
	local s12 = root and root:FindFirstChild("S12Durability")
	if s12 then
		if s12:GetAttribute("OwnsStructureHealth") ~= false then
			addError(errors, "s12_must_not_own_structure_health")
		end
		if s12:GetAttribute("PolicyMode") ~= "quote-only" then
			addError(errors, "s12_policy_mode")
		end
	else
		addError(errors, "s12_scope_missing")
	end

	local quote = DurabilityPolicy.StructureDecayQuote(100, 1, 0.5, false, 10)
	if type(quote) ~= "table" or type(quote.damage) ~= "number" or quote.damage <= 0 then
		addError(errors, "s12_decay_quote")
	else
		-- Dry-run the bridge with a stub lifecycle to prove command shape (no graph mutation).
		local stubCalls = {}
		local stub = {
			ApplyDamage = function(pieceId, rawDamage, damageType, transactionId)
				table.insert(stubCalls, {
					pieceId = pieceId,
					rawDamage = rawDamage,
					damageType = damageType,
					transactionId = transactionId,
				})
				return {
					ok = true,
					duplicate = false,
					health = 100 - rawDamage,
					maxHealth = 100,
					transactionId = transactionId,
				}
			end,
		}
		local bridged = S12B1DamageBridge.ApplyQuotedDamage(stub, quote, {
			pieceId = "i5-probe",
			transactionId = "i5:s12-probe",
		})
		if not bridged.ok
			or #stubCalls ~= 1
			or stubCalls[1].rawDamage ~= quote.damage
			or stubCalls[1].transactionId ~= "i5:s12-probe"
		then
			addError(errors, "s12_b1_damage_bridge")
		end
	end

	-- Transaction dedupe still holds (B1 hardening suite).
	local hardPassed = select(1, B1HardeningVerifier.Run())
	if not hardPassed then
		addError(errors, "b1_transaction_dedupe")
	end

	-- I3/I4 non-regression: scopes must remain PASS when present.
	if root then
		local i3 = scopeStatus(root, "I3InventoryShadow", "I3Status")
		local i4 = scopeStatus(root, "I4CraftingRuntime", "I4Status")
		if i3 ~= nil and i3 ~= "PASS" then
			addError(errors, "i3_regressed")
		end
		if i4 ~= nil and i4 ~= "PASS" then
			addError(errors, "i4_regressed")
		end
	end

	local status = #errors == 0 and "PASS" or "ERROR"
	if scope then
		scope:SetAttribute("I5Status", status)
		scope:SetAttribute("I5ErrorCount", #errors)
		scope:SetAttribute("I5Errors", table.concat(errors, ","))
		scope:SetAttribute("I5MappingCount", CraftedBuildPartMapping.Count())
		scope:SetAttribute("I5MappingGaps", table.concat(CraftedBuildPartMapping.MappingGaps(), " | "))
		scope:SetAttribute("I5SharedSurface", surfacePassed == true)
		if buildingState then
			scope:SetAttribute("I5B0Status", buildingState:GetAttribute("B0Status"))
			scope:SetAttribute("I5B1Status", buildingState:GetAttribute("B1Status"))
			scope:SetAttribute("I5MapRuntimeStatus", buildingState:GetAttribute("MapRuntimeStatus"))
		end
	end

	return status == "PASS", errors, {
		status = status,
		errorCount = #errors,
		mappingCount = CraftedBuildPartMapping.Count(),
	}
end

return I5Verifier

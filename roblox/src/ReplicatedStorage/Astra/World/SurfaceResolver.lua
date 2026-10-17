local Workspace = game:GetService("Workspace")

-- I0.2 unified physical-surface projector (World-owned).
-- Logical X/Z remain authoritative; TopY/Project only resolve a physically
-- reachable Roblox Y until real W1 terrain materialization exists.
--
-- Shared by SurvivalBridge (W6 path targets) and B1 PreviewRoot/PlaceRoot /
-- map seeder. Merges the best of the prior SurvivalBridge projector and the
-- Building SurfaceResolver:
--   * AstraBaseplate (or equivalent) fast path when the part covers X/Z
--   * downward Exclude raycast with defaults rebuilt every call
--   * flat compatibility floor fallback (Y = 0) so Y is always finite
--
-- IgnoreWater = false: water parts remain hittable for physical Y. W5 Build
-- affordance rejects wet cells separately via AffordancePolicy (maxBuildWater);
-- do not conflate physical projection with Build gating.
local SurfaceResolver = {}

local DEFAULT_FROM_Y = 256
local DEFAULT_MAX_DISTANCE = 512
local DEFAULT_BASEPLATE_NAME = "AstraBaseplate"
local DEFAULT_EXCLUDE_NAMES = { "AstraAgents", "AstraResources", "AstraStructures" }

local function appendUnique(list, seen, instance)
	if not instance or seen[instance] then
		return
	end
	seen[instance] = true
	table.insert(list, instance)
end

local function buildExclude(extra)
	local list = {}
	local seen = {}
	for _, name in ipairs(DEFAULT_EXCLUDE_NAMES) do
		appendUnique(list, seen, Workspace:FindFirstChild(name))
	end
	if extra then
		for _, instance in ipairs(extra) do
			appendUnique(list, seen, instance)
		end
	end
	return list
end

-- options (all optional):
--   exclude: array of extra Instances (e.g. current.renderFolder)
--   fromY: number, ray start height (default 256)
--   maxDistance: number, ray length downward (default 512)
--   baseplateName: string (default "AstraBaseplate")
--   skipDefaults: if true, only use caller exclude (no agents/resources/structures)
function SurfaceResolver.TopY(position, options)
	options = options or {}

	local baseplate = Workspace:FindFirstChild(options.baseplateName or DEFAULT_BASEPLATE_NAME)
	if baseplate and baseplate:IsA("BasePart") then
		local localPoint = baseplate.CFrame:PointToObjectSpace(Vector3.new(
			position.X,
			baseplate.Position.Y,
			position.Z
		))
		if math.abs(localPoint.X) <= baseplate.Size.X * 0.5
			and math.abs(localPoint.Z) <= baseplate.Size.Z * 0.5
		then
			return baseplate.Position.Y + baseplate.Size.Y * 0.5
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Rebuild every call: do NOT freeze FilterDescendantsInstances across uses.
	if options.skipDefaults then
		local filtered = {}
		local seen = {}
		for _, instance in ipairs(options.exclude or {}) do
			appendUnique(filtered, seen, instance)
		end
		params.FilterDescendantsInstances = filtered
	else
		params.FilterDescendantsInstances = buildExclude(options.exclude)
	end
	params.IgnoreWater = false

	local hit = Workspace:Raycast(
		Vector3.new(position.X, options.fromY or DEFAULT_FROM_Y, position.Z),
		Vector3.new(0, -(options.maxDistance or DEFAULT_MAX_DISTANCE), 0),
		params
	)
	if hit then
		return hit.Position.Y
	end

	-- Flat compatibility floor top.
	return 0
end

function SurfaceResolver.Project(position, options)
	return Vector3.new(position.X, SurfaceResolver.TopY(position, options), position.Z)
end

-- Default exclude names exposed for contract tests / callers that need parity.
SurfaceResolver.DefaultExcludeNames = DEFAULT_EXCLUDE_NAMES

return SurfaceResolver

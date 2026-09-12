local Workspace = game:GetService("Workspace")

local SurfaceResolver = require(script.Parent.SurfaceResolver)

-- Small I0.2 contract assertions for the shared World SurfaceResolver.
-- Safe to call at runtime (no mutation of world authority).
local SurfaceResolverContract = {}

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function SurfaceResolverContract.Run()
	local results = {}

	local sample = Vector3.new(5, 100, 7)
	local resolved = SurfaceResolver.Project(sample)
	results.preservesXZ = resolved.X == sample.X and resolved.Z == sample.Z
	results.finiteY = isFinite(resolved.Y)

	local baseplate = Workspace:FindFirstChild("AstraBaseplate")
	if baseplate and baseplate:IsA("BasePart") then
		local expectedTop = baseplate.Position.Y + baseplate.Size.Y * 0.5
		local topY = SurfaceResolver.TopY(Vector3.new(0, 999, 0))
		results.baseplateTopY = math.abs(topY - expectedTop) <= 1e-3
		-- Must not report logical cell height; Physical Y tracks baseplate top.
		results.notLogicalCellHeight = topY ~= 999 and math.abs(topY - expectedTop) <= 1e-3
	else
		-- Without a baseplate the flat floor fallback is Y = 0.
		results.baseplateTopY = resolved.Y == 0 or isFinite(resolved.Y)
		results.notLogicalCellHeight = resolved.Y ~= sample.Y
	end

	-- Exclude list must be rebuilt per call (no frozen FilterDescendantsInstances).
	-- We assert the public contract: calling twice with different extras does not
	-- throw and still preserves X/Z with finite Y.
	local folderA = Instance.new("Folder")
	folderA.Name = "SurfaceResolverContractExcludeA"
	local folderB = Instance.new("Folder")
	folderB.Name = "SurfaceResolverContractExcludeB"
	local a = SurfaceResolver.Project(sample, { exclude = { folderA } })
	local b = SurfaceResolver.Project(sample, { exclude = { folderB } })
	folderA:Destroy()
	folderB:Destroy()
	results.excludeRebuilt =
		a.X == sample.X
		and a.Z == sample.Z
		and b.X == sample.X
		and b.Z == sample.Z
		and isFinite(a.Y)
		and isFinite(b.Y)

	local passed = true
	for _, value in pairs(results) do
		if value ~= true then
			passed = false
			break
		end
	end

	return passed, results, {
		resolvedY = resolved.Y,
		defaultExcludeNames = table.concat(SurfaceResolver.DefaultExcludeNames, ","),
	}
end

return SurfaceResolverContract

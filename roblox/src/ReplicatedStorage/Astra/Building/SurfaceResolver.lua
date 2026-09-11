local Workspace = game:GetService("Workspace")

-- I0.2 boundary: logical world X/Z remains authoritative; TopY/Project only
-- resolve a physically reachable Roblox Y until real W1 terrain materialization
-- exists.
local SurfaceResolver = {}

local DEFAULT_FROM_Y = 256
local DEFAULT_MAX_DISTANCE = 512
local DEFAULT_BASEPLATE_NAME = "AstraBaseplate"

local function filteredExclude(exclude)
    if not exclude then return nil end
    local filtered = {}
    for _, instance in ipairs(exclude) do
        if instance then
            table.insert(filtered, instance)
        end
    end
    return filtered
end

-- options (all optional):
--   exclude: array of Instances to exclude from the raycast (e.g. render folder, agents folder)
--   fromY: number, ray start height (default 256)
--   maxDistance: number, ray length downward (default 512)
--   baseplateName: string (default "AstraBaseplate")
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
    params.FilterDescendantsInstances = filteredExclude(options.exclude) or {}
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

return SurfaceResolver

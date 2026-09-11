local WorldSimRoutes = {}

local MAX_RESOURCE_NODES = 12
local LINKS_PER_NODE = 3

local function positionOf(instance)
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then
        local root = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart")
        return root and root.Position or nil
    end
    return nil
end

local function addNode(nodes, id, kind, position)
    if position then
        table.insert(nodes, { id = id, kind = kind, position = position })
    end
end

function WorldSimRoutes.Update(folders, routesFolder, basePosition)
    local nodes = {}
    addNode(nodes, "colony-base", "base", basePosition or Vector3.new(0, 0, 0))

    for _, structure in ipairs(folders.structures:GetChildren()) do
        addNode(nodes, "structure:" .. structure.Name, "structure", positionOf(structure))
    end

    local resources = {}
    for _, resource in ipairs(folders.resources:GetChildren()) do
        if resource:IsA("BasePart") and resource:GetAttribute("Active") ~= false then
            table.insert(resources, resource)
        end
    end
    table.sort(resources, function(a, b) return a.Name < b.Name end)
    for i = 1, math.min(MAX_RESOURCE_NODES, #resources) do
        local resource = resources[i]
        addNode(nodes, "resource:" .. resource.Name, "resource", resource.Position)
    end

    table.sort(nodes, function(a, b) return a.id < b.id end)
    local edges = {}
    local seen = {}
    for i, node in ipairs(nodes) do
        local candidates = {}
        for j, other in ipairs(nodes) do
            if i ~= j then
                table.insert(candidates, {
                    target = other,
                    distance = (node.position - other.position).Magnitude,
                })
            end
        end
        table.sort(candidates, function(a, b)
            if a.distance == b.distance then return a.target.id < b.target.id end
            return a.distance < b.distance
        end)
        for c = 1, math.min(LINKS_PER_NODE, #candidates) do
            local target = candidates[c].target
            local a, b = node.id, target.id
            if b < a then a, b = b, a end
            local key = a .. "->" .. b
            if not seen[key] then
                seen[key] = true
                table.insert(edges, {
                    a = a,
                    b = b,
                    distance = candidates[c].distance,
                })
            end
        end
    end

    local totalDistance = 0
    for _, edge in ipairs(edges) do totalDistance += edge.distance end
    local averageDistance = #edges > 0 and totalDistance / #edges or 0

    routesFolder:SetAttribute("NodeCount", #nodes)
    routesFolder:SetAttribute("EdgeCount", #edges)
    routesFolder:SetAttribute("AverageEdgeDistance", math.floor(averageDistance * 10 + 0.5) / 10)
    routesFolder:SetAttribute("ResourceNodeCount", math.min(MAX_RESOURCE_NODES, #resources))
    return { nodes = nodes, edges = edges }
end

return WorldSimRoutes

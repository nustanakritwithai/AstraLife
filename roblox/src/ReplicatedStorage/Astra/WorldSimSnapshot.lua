local Determinism = require(script.Parent.WorldSimDeterminism)
local Grid = require(script.Parent.WorldSimGrid)

local WorldSimSnapshot = {}

local WORLD_ATTRS = {
    "WorldTick", "DayPhase", "ClockTime", "Weather", "WorldEvent", "DangerActive",
    "Stock_Wood", "Stock_Stone", "Stock_Food", "Stock_Water", "StockTotal", "StorageCapacity",
    "ActiveBuildId", "BuildProgress", "BuildStatus",
}

local AGENT_ATTRS = {
    "Role", "Goal", "Hunger", "Thirst", "Energy", "Safety", "Social", "SurvivalCritical",
    "CarryTotal", "CarryCapacity", "State",
}

local function round(value, places)
    local factor = 10 ^ (places or 2)
    return math.floor(value * factor + 0.5) / factor
end

local function positionOf(instance)
    if instance:IsA("Model") then
        local root = instance:FindFirstChild("HumanoidRootPart") or instance.PrimaryPart
        return root and root.Position or nil
    elseif instance:IsA("BasePart") then
        return instance.Position
    end
    return nil
end

local function captureAttrs(instance, names)
    local out = {}
    for _, name in ipairs(names) do
        local value = instance:GetAttribute(name)
        if value ~= nil then out[name] = value end
    end
    return out
end

local function sortedChildren(folder)
    local children = folder and folder:GetChildren() or {}
    table.sort(children, function(a, b) return a.Name < b.Name end)
    return children
end

local function canonicalValue(value)
    local valueType = typeof(value)
    if valueType == "Vector3" then
        return string.format("%.2f,%.2f,%.2f", value.X, value.Y, value.Z)
    elseif valueType == "number" then
        return string.format("%.4f", value)
    end
    return tostring(value)
end

function WorldSimSnapshot.Capture(folders, cellSize)
    local state = folders.state
    local tick = state:GetAttribute("WorldTick") or 0
    local snapshot = {
        tick = tick,
        world = captureAttrs(state, WORLD_ATTRS),
        agents = {},
        resources = {},
        structures = {},
    }

    for _, agent in ipairs(sortedChildren(folders.agents)) do
        if agent:IsA("Model") then
            local position = positionOf(agent)
            local humanoid = agent:FindFirstChildOfClass("Humanoid")
            table.insert(snapshot.agents, {
                id = agent.Name,
                position = position,
                cell = position and Grid.PositionKey(position, cellSize) or "unknown",
                health = humanoid and round(humanoid.Health, 1) or nil,
                attributes = captureAttrs(agent, AGENT_ATTRS),
            })
        end
    end

    for _, resource in ipairs(sortedChildren(folders.resources)) do
        if resource:IsA("BasePart") then
            table.insert(snapshot.resources, {
                id = resource.Name,
                resourceType = resource:GetAttribute("ResourceType") or "Unknown",
                active = resource:GetAttribute("Active") ~= false,
                amount = resource:GetAttribute("Amount") or 0,
                position = resource.Position,
                cell = Grid.PositionKey(resource.Position, cellSize),
            })
        end
    end

    for _, structure in ipairs(sortedChildren(folders.structures)) do
        local position = positionOf(structure)
        table.insert(snapshot.structures, {
            id = structure.Name,
            position = position,
            cell = position and Grid.PositionKey(position, cellSize) or "unknown",
        })
    end

    local parts = { "tick=" .. tostring(tick) }
    for _, key in ipairs(WORLD_ATTRS) do
        if snapshot.world[key] ~= nil then
            table.insert(parts, "w:" .. key .. "=" .. canonicalValue(snapshot.world[key]))
        end
    end
    for _, agent in ipairs(snapshot.agents) do
        local p = agent.position
        table.insert(parts, string.format(
            "a:%s:%s:%s:%s",
            agent.id,
            agent.cell,
            p and canonicalValue(p) or "none",
            agent.health and canonicalValue(agent.health) or "none"
        ))
        for _, key in ipairs(AGENT_ATTRS) do
            if agent.attributes[key] ~= nil then
                table.insert(parts, "aa:" .. agent.id .. ":" .. key .. "=" .. canonicalValue(agent.attributes[key]))
            end
        end
    end
    for _, resource in ipairs(snapshot.resources) do
        table.insert(parts, string.format(
            "r:%s:%s:%s:%s:%s",
            resource.id,
            resource.resourceType,
            tostring(resource.active),
            tostring(resource.amount),
            resource.cell
        ))
    end
    for _, structure in ipairs(snapshot.structures) do
        table.insert(parts, "s:" .. structure.id .. ":" .. structure.cell)
    end

    snapshot.fingerprint = Determinism.Fingerprint(parts)
    return snapshot
end

return WorldSimSnapshot

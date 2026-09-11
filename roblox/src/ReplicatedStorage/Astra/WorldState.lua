local WorldState = {}

local function ensureFolder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

function WorldState.Ensure()
    local folders = {
        agents = ensureFolder(workspace, "AstraAgents"),
        resources = ensureFolder(workspace, "AstraResources"),
        structures = ensureFolder(workspace, "AstraStructures"),
        state = ensureFolder(workspace, "AstraWorldState"),
    }

    local state = folders.state

    if state:GetAttribute("TeamResources") == nil then
        state:SetAttribute("TeamResources", 0)
    end
    if state:GetAttribute("WorldTick") == nil then
        state:SetAttribute("WorldTick", 0)
    end
    if state:GetAttribute("ActiveBuildId") == nil then
        state:SetAttribute("ActiveBuildId", "None")
    end
    if state:GetAttribute("BuildProgress") == nil then
        state:SetAttribute("BuildProgress", 0)
    end
    if state:GetAttribute("BuildStatus") == nil then
        state:SetAttribute("BuildStatus", "Idle")
    end

    return folders
end

function WorldState.GetResources()
    local folders = WorldState.Ensure()
    return folders.state:GetAttribute("TeamResources") or 0
end

function WorldState.AddResources(amount)
    local folders = WorldState.Ensure()
    local value = (folders.state:GetAttribute("TeamResources") or 0) + math.max(0, amount or 0)
    folders.state:SetAttribute("TeamResources", value)
    return value
end

function WorldState.SpendResources(amount)
    amount = math.max(0, amount or 0)
    local folders = WorldState.Ensure()
    local current = folders.state:GetAttribute("TeamResources") or 0

    if current < amount then
        return false, current
    end

    local nextValue = current - amount
    folders.state:SetAttribute("TeamResources", nextValue)
    return true, nextValue
end

function WorldState.NextTick()
    local folders = WorldState.Ensure()
    local tick = (folders.state:GetAttribute("WorldTick") or 0) + 1
    folders.state:SetAttribute("WorldTick", tick)
    return tick
end

return WorldState

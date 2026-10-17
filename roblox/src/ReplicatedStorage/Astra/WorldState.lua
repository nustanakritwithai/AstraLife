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

function WorldState.Ensure(config)
    local folders = {
        agents = ensureFolder(workspace, "AstraAgents"),
        resources = ensureFolder(workspace, "AstraResources"),
        structures = ensureFolder(workspace, "AstraStructures"),
        state = ensureFolder(workspace, "AstraWorldState"),
    }

    local state = folders.state

    local defaults = {
        WorldTick = 0,
        ActiveBuildId = "None",
        BuildProgress = 0,
        BuildStatus = "Idle",
        Stock_Wood = 0,
        Stock_Stone = 0,
        Stock_Food = 0,
        Stock_Water = 0,
        StockTotal = 0,
        StorageCapacity = config and config.StorageCapacity or 40,
        P1Status = "RUNNING",
        P2Status = "RUNNING",
    }

    for key, value in pairs(defaults) do
        if state:GetAttribute(key) == nil then
            state:SetAttribute(key, value)
        end
    end

    return folders
end

function WorldState.NextTick(config)
    local folders = WorldState.Ensure(config)
    local tick = (folders.state:GetAttribute("WorldTick") or 0) + 1
    folders.state:SetAttribute("WorldTick", tick)
    return tick
end

function WorldState.GetTick(config)
    return WorldState.Ensure(config).state:GetAttribute("WorldTick") or 0
end

return WorldState

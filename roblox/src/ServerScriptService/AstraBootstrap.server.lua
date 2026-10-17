local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)
local ResourceEconomy = require(Astra.ResourceEconomy)
local Storage = require(Astra.Storage)

local folders = WorldState.Ensure(Config)
ResourceEconomy.Ensure(folders.state, Config.StorageCapacity)

local function ensureBaseplate()
    if workspace:FindFirstChild("AstraBaseplate") then
        return
    end

    local baseplate = Instance.new("Part")
    baseplate.Name = "AstraBaseplate"
    baseplate.Size = Vector3.new(220, 1, 220)
    baseplate.Position = Vector3.new(0, -0.5, 0)
    baseplate.Anchored = true
    baseplate.Material = Enum.Material.Grass
    baseplate.Color = Color3.fromRGB(85, 135, 75)
    baseplate.Parent = workspace
end

local function ensureSpawn()
    if workspace:FindFirstChildOfClass("SpawnLocation") then
        return
    end

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "PlayerSpawn"
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Position = Vector3.new(0, 0.5, -24)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Parent = workspace
end

local function createResource(index, resourceType, position)
    local descriptor = Config.ResourceTypes[resourceType]
    local resource = Instance.new("Part")
    resource.Name = string.format("%s_%02d", resourceType, index)
    resource.Shape = Enum.PartType.Ball
    resource.Size = Vector3.new(2, 2, 2)
    resource.Position = position
    resource.Anchored = true
    resource.CanCollide = false
    resource.CanTouch = false
    resource.Material = descriptor.material
    resource.Color = descriptor.color
    resource:SetAttribute("Active", true)
    resource:SetAttribute("Amount", descriptor.yield or 1)
    resource:SetAttribute("ResourceType", resourceType)
    resource.Parent = folders.resources
    return resource
end

local function ensureResources()
    if not Config.CreateDemoResources or #folders.resources:GetChildren() > 0 then
        return
    end

    -- Deterministic P1-P3 acceptance layout.
    -- Scout can discover remote Wood while Gatherer also has requested materials
    -- available around the colony for Build Site delivery.
    local specs = {
        {"Wood",  1, Vector3.new(-30, 1.2, 0)},
        {"Wood",  2, Vector3.new(-24, 1.2, 10)},
        {"Stone", 1, Vector3.new(-18, 1.2, -13)},
        {"Stone", 2, Vector3.new(28, 1.2, 14)},
        {"Food",  1, Vector3.new(8, 1.2, 28)},
        {"Food",  2, Vector3.new(32, 1.2, -8)},
        {"Water", 1, Vector3.new(-8, 1.2, 30)},
        {"Water", 2, Vector3.new(20, 1.2, -28)},
    }

    for _, spec in ipairs(specs) do
        createResource(spec[2], spec[1], spec[3])
    end
end

local function roleColor(role)
    if role == Config.Roles.Scout then
        return Color3.fromRGB(75, 165, 255)
    elseif role == Config.Roles.Gatherer then
        return Color3.fromRGB(90, 220, 120)
    elseif role == Config.Roles.Builder then
        return Color3.fromRGB(255, 175, 70)
    end
    return Color3.fromRGB(200, 200, 210)
end

local function tintAgent(model, role)
    local color = roleColor(role)
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then
            obj.Color = color
        end
    end
end

local function createR15Agent(name, role, position)
    local description = Instance.new("HumanoidDescription")
    local ok, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
    end)
    description:Destroy()

    if not ok or not model then
        warn("[AstraBootstrap] Could not create R15 agent:", name)
        return nil
    end

    model.Name = name
    model:SetAttribute("Role", role)
    model:SetAttribute("IsAstraAgent", true)
    model.Parent = folders.agents
    model:PivotTo(CFrame.new(position))
    tintAgent(model, role)
    return model
end

local function ensureAgents()
    if not Config.CreateDemoAgents or #folders.agents:GetChildren() > 0 then
        return
    end

    createR15Agent("AstraScout", Config.Roles.Scout, Vector3.new(-20, 3, 0))
    createR15Agent("AstraGatherer", Config.Roles.Gatherer, Vector3.new(10, 3, 0))
    createR15Agent("AstraBuilder", Config.Roles.Builder, Vector3.new(2, 3, 8))
end

ensureBaseplate()
ensureSpawn()
Storage.FindOrCreate(folders, Config)

if folders.state:GetAttribute("ColonyOrigin") == nil then
    folders.state:SetAttribute("ColonyOrigin", Vector3.new(0, 0, 0))
end

folders.state:SetAttribute("Runtime", "Rojo")
folders.state:SetAttribute("Version", Config.RuntimeVersion)
folders.state:SetAttribute("P3_RequestMode", Config.P3RequestMode == true)
folders.state:SetAttribute("P1Status", "RUNNING")
folders.state:SetAttribute("P2Status", "RUNNING")
folders.state:SetAttribute("P3Status", "RUNNING")

ensureResources()
ensureAgents()

print("[AstraLife] Roblox Rojo P3 Construction V2 world bootstrapped")

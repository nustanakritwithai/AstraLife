local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)

local folders = WorldState.Ensure()

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

local function createResource(index, position)
    local resource = Instance.new("Part")
    resource.Name = string.format("Resource%02d", index)
    resource.Shape = Enum.PartType.Ball
    resource.Size = Vector3.new(2, 2, 2)
    resource.Position = position
    resource.Anchored = true
    resource.CanCollide = false
    resource.CanTouch = false
    resource.Material = Enum.Material.Neon
    resource.Color = Color3.fromRGB(70, 255, 120)
    resource:SetAttribute("Active", true)
    resource:SetAttribute("Amount", 1)
    resource.Parent = folders.resources
    return resource
end

local function ensureResources()
    if not Config.CreateDemoResources or #folders.resources:GetChildren() > 0 then
        return
    end

    local origin = folders.state:GetAttribute("ColonyOrigin")
    if typeof(origin) ~= "Vector3" then
        origin = Vector3.new(0, 0, 0)
    end

    local offsets = {
        Vector3.new(16, 1.2, 8),
        Vector3.new(-14, 1.2, 18),
        Vector3.new(24, 1.2, -15),
        Vector3.new(-22, 1.2, -12),
        Vector3.new(5, 1.2, 30),
        Vector3.new(-30, 1.2, 6),
        Vector3.new(32, 1.2, 15),
        Vector3.new(10, 1.2, -32),
    }

    for i = 1, math.min(Config.DemoResourceCount, #offsets) do
        createResource(i, origin + offsets[i])
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
        return Players:CreateHumanoidModelFromDescription(
            description,
            Enum.HumanoidRigType.R15
        )
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

    createR15Agent("AstraScout", Config.Roles.Scout, Vector3.new(-7, 3, 0))
    createR15Agent("AstraGatherer", Config.Roles.Gatherer, Vector3.new(0, 3, 0))
    createR15Agent("AstraBuilder", Config.Roles.Builder, Vector3.new(7, 3, 0))
end

ensureBaseplate()
ensureSpawn()

if folders.state:GetAttribute("ColonyOrigin") == nil then
    folders.state:SetAttribute("ColonyOrigin", Vector3.new(0, 0, 0))
end

folders.state:SetAttribute("Runtime", "Rojo")
folders.state:SetAttribute("Version", "0.1.0-rojo")

ensureResources()
ensureAgents()

print("[AstraLife] Roblox Rojo world bootstrapped")

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
    if workspace:FindFirstChild("AstraBaseplate") then return end
    local baseplate = Instance.new("Part")
    baseplate.Name = "AstraBaseplate"
    local size = Config.LivingWorldPhysicalSize or 220
    baseplate.Size = Vector3.new(size, 1, size)
    baseplate.Position = Vector3.new(0, -0.5, 0)
    baseplate.Anchored = true
    baseplate.Material = Enum.Material.Grass
    baseplate.Color = Color3.fromRGB(85, 135, 75)
    baseplate:SetAttribute("LivingWorldCompatibilityFloor", true)
    baseplate.Parent = workspace
end

local function ensureSpawn()
    if workspace:FindFirstChildOfClass("SpawnLocation") then return end
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
    resource:SetAttribute("ScaleNode", true)
    resource:SetAttribute("ResourceAuthority", "LegacyPhysical")
    resource.Parent = folders.resources
    return resource
end

local function ensureResources()
    if not Config.CreateDemoResources or #folders.resources:GetChildren() > 0 then return end

    -- Keep one deterministic P1 remote-knowledge case. Legacy physical nodes stay
    -- during W7 integration because Stone is not yet a Living World transaction.
    createResource(1, "Wood", Vector3.new(-50, 1.2, 0))

    local resourceTypes = {"Wood", "Stone", "Food", "Water"}
    local perTypeIndex = {Wood = 1, Stone = 0, Food = 0, Water = 0}

    for i = 2, Config.ScaleResourceNodeCount do
        local resourceType = resourceTypes[((i - 2) % #resourceTypes) + 1]
        perTypeIndex[resourceType] += 1

        local angle = math.rad(((i - 2) * 360 / (Config.ScaleResourceNodeCount - 1) + ((i % 3) * 9)) % 360)
        local radius = 30 + ((i * 7) % 27)
        local position = Vector3.new(math.cos(angle) * radius, 1.2, math.sin(angle) * radius)
        createResource(perTypeIndex[resourceType], resourceType, position)
    end

    folders.state:SetAttribute("ScaleResourceCount", #folders.resources:GetChildren())
end

local function roleColor(role)
    if role == Config.Roles.Scout then return Color3.fromRGB(75, 165, 255) end
    if role == Config.Roles.Gatherer then return Color3.fromRGB(90, 220, 120) end
    if role == Config.Roles.Builder then return Color3.fromRGB(255, 175, 70) end
    return Color3.fromRGB(200, 200, 210)
end

local function tintAgent(model, role)
    local color = roleColor(role)
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then obj.Color = color end
    end
end

local function createR15Agent(name, role, position, scaleIndex)
    local description = Instance.new("HumanoidDescription")
    local ok, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
    end)
    description:Destroy()
    if not ok or not model then warn("[AstraBootstrap] Could not create R15 agent:", name) return nil end

    model.Name = name
    model:SetAttribute("Role", role)
    model:SetAttribute("IsAstraAgent", true)
    model:SetAttribute("ScaleIndex", scaleIndex)
    model:SetAttribute("DecisionPhaseSeconds", (scaleIndex - 1) * Config.DecisionStaggerStepSeconds)
    model.Parent = folders.agents
    model:PivotTo(CFrame.new(position))
    tintAgent(model, role)
    return model
end

local function ensureAgents()
    if not Config.CreateDemoAgents or #folders.agents:GetChildren() > 0 then return end

    local specs = {
        {"AstraScout01", Config.Roles.Scout, Vector3.new(-36, 3, 0)},
        {"AstraScout02", Config.Roles.Scout, Vector3.new(36, 3, 0)},
        {"AstraGatherer01", Config.Roles.Gatherer, Vector3.new(-12, 3, 0)},
        {"AstraGatherer02", Config.Roles.Gatherer, Vector3.new(-8, 3, 12)},
        {"AstraGatherer03", Config.Roles.Gatherer, Vector3.new(8, 3, 12)},
        {"AstraGatherer04", Config.Roles.Gatherer, Vector3.new(12, 3, 0)},
        {"AstraGatherer05", Config.Roles.Gatherer, Vector3.new(8, 3, -12)},
        {"AstraGatherer06", Config.Roles.Gatherer, Vector3.new(-8, 3, -12)},
        {"AstraGatherer07", Config.Roles.Gatherer, Vector3.new(0, 3, 18)},
        {"AstraBuilder01", Config.Roles.Builder, Vector3.new(3, 3, 5)},
        {"AstraBuilder02", Config.Roles.Builder, Vector3.new(-4, 3, 7)},
        {"AstraBuilder03", Config.Roles.Builder, Vector3.new(5, 3, -6)},
    }

    for i, spec in ipairs(specs) do
        createR15Agent(spec[1], spec[2], spec[3], i)
    end

    folders.state:SetAttribute("ScaleAgentCount", #folders.agents:GetChildren())
    folders.state:SetAttribute("ScaleSpawnComplete", #folders.agents:GetChildren() == Config.ScaleAgentCount)
end

local function seedSurvivalStock()
    if folders.state:GetAttribute("P4_SurvivalStockSeeded") == true then return end
    ResourceEconomy.DepositToStorage(folders.state, "Food", Config.DemoStartingFood)
    ResourceEconomy.DepositToStorage(folders.state, "Water", Config.DemoStartingWater)
    folders.state:SetAttribute("P4_SurvivalStockSeeded", true)
end

ensureBaseplate()
ensureSpawn()
Storage.FindOrCreate(folders, Config)

if folders.state:GetAttribute("ColonyOrigin") == nil then folders.state:SetAttribute("ColonyOrigin", Vector3.new(0, 0, 0)) end
folders.state:SetAttribute("Runtime", "Rojo")
folders.state:SetAttribute("Version", Config.RuntimeVersion)
folders.state:SetAttribute("P3_RequestMode", Config.P3RequestMode == true)
folders.state:SetAttribute("P1Status", "RUNNING")
folders.state:SetAttribute("P2Status", "RUNNING")
folders.state:SetAttribute("P3Status", "RUNNING")
folders.state:SetAttribute("P4Status", "RUNNING")
folders.state:SetAttribute("P5Status", "RUNNING")
folders.state:SetAttribute("P6Status", "RUNNING")
folders.state:SetAttribute("P7Status", "RUNNING")
folders.state:SetAttribute("Scale12Status", "RUNNING")
folders.state:SetAttribute("Scale12LongRunStatus", "RUNNING")
folders.state:SetAttribute("P75W7IntegrationStatus", "BOOTING")
-- I6: outcome-only XP must be on before AgentService starts brains.
folders.state:SetAttribute("P7_I6OutcomeOnly", true)

ensureResources()
ensureAgents()
seedSurvivalStock()

print("[AstraLife] P7.5 + W7 integration bootstrap - 12 agents / 24 legacy compatibility resources")

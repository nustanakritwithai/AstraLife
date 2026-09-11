local Lighting = game:GetService("Lighting")

local WorldSimulation = {}

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

local function dayState(tick, config)
    local t = tick % config.DayLengthTicks
    local phase
    if t < config.DawnEndTick then
        phase = "Dawn"
    elseif t < config.DayEndTick then
        phase = "Day"
    elseif t < config.DuskEndTick then
        phase = "Dusk"
    else
        phase = "Night"
    end

    local clockTime = (t / config.DayLengthTicks) * 24
    return phase, clockTime, phase == "Night"
end

local function weatherState(tick, config)
    local period = math.max(1, config.WeatherPeriodTicks)
    local index = math.floor(tick / period) % #config.WeatherSequence + 1
    return config.WeatherSequence[index]
end

local function applyLighting(phase, weather, clockTime)
    Lighting.ClockTime = clockTime

    if phase == "Night" then
        Lighting.Brightness = 1.2
        Lighting.OutdoorAmbient = Color3.fromRGB(55, 65, 95)
    elseif phase == "Dawn" or phase == "Dusk" then
        Lighting.Brightness = 2
        Lighting.OutdoorAmbient = Color3.fromRGB(120, 110, 105)
    else
        Lighting.Brightness = 2.6
        Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
    end

    if weather == "Rain" then
        Lighting.FogEnd = 180
        Lighting.FogColor = Color3.fromRGB(120, 135, 150)
    elseif weather == "Storm" then
        Lighting.FogEnd = 110
        Lighting.FogColor = Color3.fromRGB(80, 90, 105)
        Lighting.Brightness = math.min(Lighting.Brightness, 1.15)
    else
        Lighting.FogEnd = 100000
    end
end

local function ensureDangerZone(config)
    local folder = ensureFolder(workspace, "AstraDangerZones")
    local zone = folder:FindFirstChild("StormField")
    if zone then
        return zone
    end

    zone = Instance.new("Part")
    zone.Name = "StormField"
    zone.Size = config.DangerZoneSize
    zone.Position = config.DangerZonePosition
    zone.Anchored = true
    zone.CanCollide = false
    zone.CanTouch = false
    zone.Material = Enum.Material.ForceField
    zone.Color = Color3.fromRGB(220, 70, 70)
    zone.Transparency = 0.78
    zone:SetAttribute("IsDangerZone", true)
    zone.Parent = folder
    return zone
end

local function spawnThreat(worldState, tick, config)
    local current = workspace:FindFirstChild("P5_StormThreat")
    if current then
        return current
    end

    local model = Instance.new("Model")
    model.Name = "P5_StormThreat"
    model:SetAttribute("IsThreat", true)
    model:SetAttribute("SpawnTick", tick)
    model:SetAttribute("ExpireTick", tick + config.ThreatDurationTicks)

    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(3, 5, 3)
    root.Position = config.DangerZonePosition + Vector3.new(0, 2.5, 0)
    root.Anchored = true
    root.CanCollide = false
    root.Material = Enum.Material.Neon
    root.Color = Color3.fromRGB(255, 70, 70)
    root.Parent = model

    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.Parent = model

    model.PrimaryPart = root
    model.Parent = workspace

    worldState:SetAttribute("P5_ThreatSpawned", true)
    worldState:SetAttribute("DangerActive", true)
    return model
end

local function updateThreat(worldState, tick, weather, isNight, config)
    local threat = workspace:FindFirstChild("P5_StormThreat")

    if threat then
        local expireTick = threat:GetAttribute("ExpireTick") or tick
        if tick >= expireTick then
            threat:Destroy()
            worldState:SetAttribute("DangerActive", false)
            threat = nil
        end
    end

    if not threat and (weather == "Storm" or isNight) then
        spawnThreat(worldState, tick, config)
    end
end

local function countBonusNodes(resources)
    local count = 0
    for _, resource in ipairs(resources:GetChildren()) do
        if resource:GetAttribute("P5Regenerated") == true then
            count += 1
        end
    end
    return count
end

local function growResource(folders, tick, weather, config)
    if tick % config.WorldResourceGrowthInterval ~= 0 then
        return
    end
    if countBonusNodes(folders.resources) >= config.WorldResourceMaxBonusNodes then
        return
    end

    local resourceType
    if weather == "Rain" then
        resourceType = (tick % 2 == 0) and "Water" or "Food"
    elseif weather == "Storm" then
        resourceType = "Water"
    else
        resourceType = (tick % 3 == 0) and "Food" or "Wood"
    end

    local descriptor = config.ResourceTypes[resourceType]
    if not descriptor then
        return
    end

    local index = countBonusNodes(folders.resources) + 1
    local angle = math.rad((tick * 71) % 360)
    local radius = 22 + ((tick * 5) % 18)

    local resource = Instance.new("Part")
    resource.Name = string.format("P5_%s_%02d", resourceType, index)
    resource.Shape = Enum.PartType.Ball
    resource.Size = Vector3.new(2, 2, 2)
    resource.Position = Vector3.new(math.cos(angle) * radius, 1.2, math.sin(angle) * radius)
    resource.Anchored = true
    resource.CanCollide = false
    resource.CanTouch = false
    resource.Material = descriptor.material
    resource.Color = descriptor.color
    resource:SetAttribute("Active", true)
    resource:SetAttribute("Amount", descriptor.yield or 1)
    resource:SetAttribute("ResourceType", resourceType)
    resource:SetAttribute("P5Regenerated", true)
    resource:SetAttribute("SpawnTick", tick)
    resource.Parent = folders.resources

    folders.state:SetAttribute("P5_ResourceRegenerated", true)
    folders.state:SetAttribute("P5_LastRegeneratedType", resourceType)
end

function WorldSimulation.Initialize(folders, config)
    ensureDangerZone(config)
    local state = folders.state
    if state:GetAttribute("DayPhase") == nil then state:SetAttribute("DayPhase", "Dawn") end
    if state:GetAttribute("Weather") == nil then state:SetAttribute("Weather", "Clear") end
    if state:GetAttribute("IsNight") == nil then state:SetAttribute("IsNight", false) end
    if state:GetAttribute("DangerActive") == nil then state:SetAttribute("DangerActive", false) end
    state:SetAttribute("P5Status", "RUNNING")
end

function WorldSimulation.Tick(folders, tick, config)
    local state = folders.state
    local previousPhase = state:GetAttribute("DayPhase")
    local previousWeather = state:GetAttribute("Weather")

    local phase, clockTime, isNight = dayState(tick, config)
    local weather = weatherState(tick, config)

    state:SetAttribute("DayPhase", phase)
    state:SetAttribute("ClockTime", clockTime)
    state:SetAttribute("IsNight", isNight)
    state:SetAttribute("Weather", weather)
    state:SetAttribute("WorldEvent", weather == "Storm" and "StormFront" or (isNight and "NightCycle" or "None"))

    if previousPhase and previousPhase ~= phase then
        state:SetAttribute("P5_DayNightChanged", true)
    end
    if previousWeather and previousWeather ~= weather then
        state:SetAttribute("P5_WeatherChanged", true)
    end
    if weather == "Storm" or isNight then
        state:SetAttribute("P5_WorldEventTriggered", true)
    end

    applyLighting(phase, weather, clockTime)
    updateThreat(state, tick, weather, isNight, config)
    growResource(folders, tick, weather, config)
end

return WorldSimulation

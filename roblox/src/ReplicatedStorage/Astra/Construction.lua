local ResourceEconomy = require(script.Parent.ResourceEconomy)

local Construction = {}

local activeBuild = nil
local RESOURCE_TYPES = {"Wood", "Stone", "Food", "Water"}

local function recipeText(recipe)
    local parts = {}
    for resourceType, amount in pairs(recipe or {}) do
        table.insert(parts, string.format("%s:%d", resourceType, amount))
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function buildPosition(config, blueprint)
    return config.StoragePosition + blueprint.offset + Vector3.new(0, 1.5, 0)
end

local function createStructurePart(blueprint, position)
    local part = Instance.new("Part")
    part.Name = blueprint.id
    part.Anchored = true
    part.CanCollide = true
    part.Position = position
    part:SetAttribute("BlueprintId", blueprint.id)
    part:SetAttribute("BuildComplete", true)

    if blueprint.id == "Campfire" then
        part.Size = Vector3.new(4, 1, 4)
        part.Material = Enum.Material.Slate
        part.Color = Color3.fromRGB(100, 90, 80)
    elseif blueprint.id == "Shelter" then
        part.Size = Vector3.new(10, 6, 8)
        part.Material = Enum.Material.WoodPlanks
        part.Color = Color3.fromRGB(130, 90, 55)
    elseif blueprint.id == "Storage" then
        part.Size = Vector3.new(8, 5, 8)
        part.Material = Enum.Material.WoodPlanks
        part.Color = Color3.fromRGB(115, 80, 50)
    else
        part.Size = Vector3.new(5, 12, 5)
        part.Material = Enum.Material.WoodPlanks
        part.Color = Color3.fromRGB(105, 75, 45)
    end

    return part
end

local function createSiteMarker(blueprint, position, config)
    local marker = Instance.new("Part")
    marker.Name = "BuildSite_" .. blueprint.id
    marker.Size = Vector3.new(8, 0.5, 8)
    marker.Position = position - Vector3.new(0, 1.25, 0)
    marker.Anchored = true
    marker.CanCollide = false
    marker.Material = Enum.Material.ForceField
    marker.Color = Color3.fromRGB(255, 190, 70)
    marker.Transparency = config.BuildSiteMarkerTransparency or 0.55
    marker:SetAttribute("IsBuildSite", true)
    marker:SetAttribute("BlueprintId", blueprint.id)

    local gui = Instance.new("BillboardGui")
    gui.Name = "BuildSiteGui"
    gui.Size = UDim2.fromOffset(240, 70)
    gui.StudsOffset = Vector3.new(0, 3.5, 0)
    gui.AlwaysOnTop = true
    gui.Parent = marker

    local label = Instance.new("TextLabel")
    label.Name = "Status"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundColor3 = Color3.fromRGB(30, 25, 18)
    label.BackgroundTransparency = 0.2
    label.TextColor3 = Color3.fromRGB(255, 235, 190)
    label.TextWrapped = true
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = blueprint.displayName .. "\nWaiting for materials"
    label.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = label

    return marker, label
end

local function resetMaterialLedger(worldState, recipe)
    local totalRequired = 0
    for _, resourceType in ipairs(RESOURCE_TYPES) do
        local required = (recipe and recipe[resourceType]) or 0
        worldState:SetAttribute("P3_Required_" .. resourceType, required)
        worldState:SetAttribute("P3_Delivered_" .. resourceType, 0)
        totalRequired += required
    end
    worldState:SetAttribute("BuildRequired", totalRequired)
    worldState:SetAttribute("P3_MaterialsReady", totalRequired == 0)
end

local function missingText(worldState)
    local parts = {}
    for _, resourceType in ipairs(RESOURCE_TYPES) do
        local missing = ResourceEconomy.GetBuildMissing(worldState, resourceType)
        if missing > 0 then
            table.insert(parts, resourceType .. " " .. tostring(missing))
        end
    end
    if #parts == 0 then
        return "materials ready"
    end
    return table.concat(parts, " / ")
end

local function updateSiteLabel(active, worldState)
    if not active or not active.statusLabel or not active.statusLabel.Parent then
        return
    end

    if ResourceEconomy.BuildSiteReady(worldState) then
        local progress = worldState:GetAttribute("BuildProgress") or 0
        active.statusLabel.Text = string.format("%s\nMaterials ready • Build %d%%", active.blueprint.displayName, progress)
    else
        active.statusLabel.Text = string.format("%s\nNeed: %s", active.blueprint.displayName, missingText(worldState))
    end
end

function Construction.GetNextBlueprint(folders, config)
    for _, blueprint in ipairs(config.Blueprints) do
        if not folders.structures:FindFirstChild(blueprint.id) then
            return blueprint
        end
    end
    return nil
end

function Construction.GetActive()
    return activeBuild
end

function Construction.TryStart(builder, folders, config, tick)
    if activeBuild then
        return activeBuild
    end

    local blueprint = Construction.GetNextBlueprint(folders, config)
    if not blueprint then
        return nil, "complete"
    end

    local position = buildPosition(config, blueprint)
    local marker, statusLabel = createSiteMarker(blueprint, position, config)
    marker.Parent = folders.structures

    local buildId = string.format("%s:%d", blueprint.id, tick)

    resetMaterialLedger(folders.state, blueprint.recipe)

    activeBuild = {
        id = buildId,
        blueprint = blueprint,
        position = position,
        progress = 0,
        startedTick = tick,
        worker = builder.Name,
        marker = marker,
        statusLabel = statusLabel,
    }

    folders.state:SetAttribute("ActiveBuildId", blueprint.id)
    folders.state:SetAttribute("P3_BuildId", buildId)
    folders.state:SetAttribute("P3_BuildSitePosition", position)
    folders.state:SetAttribute("P3_Recipe", recipeText(blueprint.recipe))
    folders.state:SetAttribute("P3_SiteCreated", true)
    folders.state:SetAttribute("P3_MaterialsRequested", true)
    folders.state:SetAttribute("BuildStatus", "AwaitingMaterials")
    folders.state:SetAttribute("BuildProgress", 0)
    folders.state:SetAttribute("ActiveBuildWorker", builder.Name)

    updateSiteLabel(activeBuild, folders.state)

    return activeBuild, "site_created"
end

function Construction.Step(builder, folders, config, tick)
    local active = activeBuild
    if not active then
        return false, "no_active_build"
    end

    local root = builder:FindFirstChild("HumanoidRootPart")
    if not root then
        return false, "no_root"
    end

    local distance = (active.position - root.Position).Magnitude
    if distance > config.ArrivalDistance + 2 then
        return false, "too_far", active.position
    end

    if not ResourceEconomy.BuildSiteReady(folders.state) then
        folders.state:SetAttribute("BuildStatus", "AwaitingMaterials")
        folders.state:SetAttribute("P3_BuilderWaited", true)
        updateSiteLabel(active, folders.state)
        return false, "awaiting_materials", missingText(folders.state)
    end

    folders.state:SetAttribute("BuildStatus", "Building")
    folders.state:SetAttribute("P2_BuilderSpentRecipe", true)

    active.progress += 1
    local percent = math.clamp(math.floor((active.progress / active.blueprint.buildSteps) * 100), 0, 100)
    folders.state:SetAttribute("BuildProgress", percent)
    folders.state:SetAttribute("P3_BuildProgress", true)
    updateSiteLabel(active, folders.state)

    if active.progress < active.blueprint.buildSteps then
        return true, "progress", percent
    end

    local structure = createStructurePart(active.blueprint, active.position)
    structure:SetAttribute("CompletedBy", builder.Name)
    structure:SetAttribute("CompletedTick", tick)
    structure:SetAttribute("P3MaterialsDelivered", true)
    structure.Parent = folders.structures

    if active.marker and active.marker.Parent then
        active.marker:Destroy()
    end

    folders.state:SetAttribute("BuildStatus", "Idle")
    folders.state:SetAttribute("BuildProgress", 100)
    folders.state:SetAttribute("ActiveBuildId", "None")
    folders.state:SetAttribute("ActiveBuildWorker", "None")
    folders.state:SetAttribute("P3_BuildCompleted", true)
    folders.state:SetAttribute("P3_LastCompletedBlueprint", active.blueprint.id)
    folders.state:SetAttribute("P3_LastBuildMaterialsReady", true)
    folders.state:SetAttribute("P3_MaterialsReady", false)

    local completed = active
    activeBuild = nil

    return true, "completed", completed
end

return Construction

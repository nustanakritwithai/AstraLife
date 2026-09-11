local ResourceEconomy = require(script.Parent.ResourceEconomy)

local Construction = {}

local activeBuild = nil

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

    if not ResourceEconomy.CanAfford(folders.state, blueprint.recipe) then
        return nil, "insufficient_resources"
    end

    if not ResourceEconomy.Spend(folders.state, blueprint.recipe) then
        return nil, "spend_failed"
    end

    folders.state:SetAttribute("P2_BuilderSpentRecipe", true)
    folders.state:SetAttribute("LastBuildRecipe", recipeText(blueprint.recipe))

    activeBuild = {
        blueprint = blueprint,
        position = buildPosition(config, blueprint),
        progress = 0,
        startedTick = tick,
        worker = builder.Name,
    }

    folders.state:SetAttribute("ActiveBuildId", blueprint.id)
    folders.state:SetAttribute("BuildStatus", "Building")
    folders.state:SetAttribute("BuildProgress", 0)
    folders.state:SetAttribute("ActiveBuildWorker", builder.Name)

    return activeBuild, "started"
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

    active.progress += 1
    local percent = math.clamp(math.floor((active.progress / active.blueprint.buildSteps) * 100), 0, 100)
    folders.state:SetAttribute("BuildProgress", percent)

    if active.progress < active.blueprint.buildSteps then
        return true, "progress", percent
    end

    local structure = createStructurePart(active.blueprint, active.position)
    structure:SetAttribute("CompletedBy", builder.Name)
    structure:SetAttribute("CompletedTick", tick)
    structure.Parent = folders.structures

    folders.state:SetAttribute("BuildStatus", "Idle")
    folders.state:SetAttribute("BuildProgress", 100)
    folders.state:SetAttribute("ActiveBuildId", "None")
    folders.state:SetAttribute("ActiveBuildWorker", "None")

    local completed = active
    activeBuild = nil

    return true, "completed", completed
end

return Construction

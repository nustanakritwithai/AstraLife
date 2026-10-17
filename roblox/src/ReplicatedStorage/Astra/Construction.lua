local WorldState = require(script.Parent.WorldState)

local Construction = {}

local activeBuild = nil

local function createPart(parent, name, size, cframe, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = true
    part.Color = color or Color3.fromRGB(130, 95, 65)
    part.Material = material or Enum.Material.WoodPlanks
    part.Parent = parent
    return part
end

local function getOrigin(folders)
    local origin = folders.state:GetAttribute("ColonyOrigin")
    if typeof(origin) == "Vector3" then
        return origin
    end
    return Vector3.new(0, 0, 0)
end

local function structureName(id)
    return "Structure_" .. id
end

function Construction.GetNextBlueprint(folders, config)
    for _, blueprint in ipairs(config.Blueprints) do
        if not folders.structures:FindFirstChild(structureName(blueprint.id)) then
            return blueprint
        end
    end
    return nil
end

local function makeBuildSite(folders, blueprint, position)
    local site = Instance.new("Part")
    site.Name = "BuildSite_" .. blueprint.id
    site.Size = Vector3.new(8, 0.35, 8)
    site.Position = position + Vector3.new(0, 0.2, 0)
    site.Anchored = true
    site.CanCollide = false
    site.Material = Enum.Material.Neon
    site.Color = Color3.fromRGB(255, 190, 60)
    site.Transparency = 0.25
    site:SetAttribute("BlueprintId", blueprint.id)
    site:SetAttribute("BuildProgress", 0)
    site.Parent = folders.structures
    return site
end

local function completeStructure(folders, blueprint, position, completedBy, tick)
    local model = Instance.new("Model")
    model.Name = structureName(blueprint.id)
    model:SetAttribute("BlueprintId", blueprint.id)
    model:SetAttribute("CompletedBy", completedBy)
    model:SetAttribute("CompletedTick", tick)
    model.Parent = folders.structures

    if blueprint.id == "Campfire" then
        createPart(model, "Base", Vector3.new(4, 0.5, 4), CFrame.new(position + Vector3.new(0, 0.25, 0)), Color3.fromRGB(80, 70, 60), Enum.Material.Slate)
        local flame = createPart(model, "Fire", Vector3.new(1.4, 2.5, 1.4), CFrame.new(position + Vector3.new(0, 1.7, 0)), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
        flame.Shape = Enum.PartType.Ball
        flame.CanCollide = false
    elseif blueprint.id == "Shelter" then
        createPart(model, "Floor", Vector3.new(10, 0.5, 8), CFrame.new(position + Vector3.new(0, 0.25, 0)))
        createPart(model, "BackWall", Vector3.new(10, 5, 0.5), CFrame.new(position + Vector3.new(0, 2.75, 3.75)))
        createPart(model, "LeftWall", Vector3.new(0.5, 5, 8), CFrame.new(position + Vector3.new(-4.75, 2.75, 0)))
        createPart(model, "RightWall", Vector3.new(0.5, 5, 8), CFrame.new(position + Vector3.new(4.75, 2.75, 0)))
        createPart(model, "Roof", Vector3.new(11, 0.6, 9), CFrame.new(position + Vector3.new(0, 5.4, 0)), Color3.fromRGB(90, 65, 45))
    elseif blueprint.id == "Storage" then
        createPart(model, "StorageBody", Vector3.new(7, 5, 7), CFrame.new(position + Vector3.new(0, 2.5, 0)), Color3.fromRGB(155, 112, 65))
        createPart(model, "Door", Vector3.new(2.5, 3.5, 0.3), CFrame.new(position + Vector3.new(0, 1.9, -3.65)), Color3.fromRGB(75, 55, 40))
    elseif blueprint.id == "WatchTower" then
        createPart(model, "Tower", Vector3.new(3, 11, 3), CFrame.new(position + Vector3.new(0, 5.5, 0)), Color3.fromRGB(115, 82, 55))
        createPart(model, "Platform", Vector3.new(8, 0.6, 8), CFrame.new(position + Vector3.new(0, 11.2, 0)), Color3.fromRGB(145, 100, 60))
        createPart(model, "Roof", Vector3.new(9, 0.5, 9), CFrame.new(position + Vector3.new(0, 14.5, 0)), Color3.fromRGB(80, 55, 40))
        for _, x in ipairs({-3.2, 3.2}) do
            for _, z in ipairs({-3.2, 3.2}) do
                createPart(model, "Post", Vector3.new(0.4, 3, 0.4), CFrame.new(position + Vector3.new(x, 12.8, z)))
            end
        end
    end

    return model
end

function Construction.GetActive()
    return activeBuild
end

function Construction.TryStart(agent, folders, config, tick)
    if activeBuild then
        return activeBuild, false
    end

    local blueprint = Construction.GetNextBlueprint(folders, config)
    if not blueprint then
        return nil, false
    end

    local paid = WorldState.SpendResources(blueprint.cost)
    if not paid then
        return nil, false
    end

    local position = getOrigin(folders) + blueprint.offset
    local site = makeBuildSite(folders, blueprint, position)

    activeBuild = {
        blueprint = blueprint,
        position = position,
        progress = 0,
        steps = blueprint.buildSteps,
        site = site,
        startedBy = agent.Name,
        startedTick = tick,
    }

    folders.state:SetAttribute("ActiveBuildId", blueprint.id)
    folders.state:SetAttribute("BuildStatus", "Building")
    folders.state:SetAttribute("BuildProgress", 0)
    folders.state:SetAttribute("BuildRequired", blueprint.buildSteps)
    folders.state:SetAttribute("ActiveBuildWorker", agent.Name)

    return activeBuild, true
end

function Construction.Step(agent, folders, config, tick)
    if agent:GetAttribute("Role") ~= config.Roles.Builder then
        return false, "not_builder"
    end

    local build = activeBuild
    if not build then
        build = Construction.TryStart(agent, folders, config, tick)
    end
    if not build then
        return false, "no_build_available"
    end

    local root = agent:FindFirstChild("HumanoidRootPart")
    if not root then
        return false, "no_root"
    end

    if (root.Position - build.position).Magnitude > config.ArrivalDistance + 2 then
        return false, "too_far", build.position
    end

    build.progress += 1
    build.site:SetAttribute("BuildProgress", build.progress)

    local percent = math.floor(math.clamp(build.progress / build.steps, 0, 1) * 100)
    folders.state:SetAttribute("BuildProgress", percent)
    folders.state:SetAttribute("ActiveBuildWorker", agent.Name)

    if build.progress >= build.steps then
        if build.site and build.site.Parent then
            build.site:Destroy()
        end

        local completed = completeStructure(
            folders,
            build.blueprint,
            build.position,
            agent.Name,
            tick
        )

        folders.state:SetAttribute("LastCompletedBuild", build.blueprint.id)
        folders.state:SetAttribute("ActiveBuildId", "None")
        folders.state:SetAttribute("BuildStatus", "Complete")
        folders.state:SetAttribute("BuildProgress", 100)
        folders.state:SetAttribute("ActiveBuildWorker", "None")

        activeBuild = nil
        return true, "completed", completed
    end

    return true, "progress", percent
end

return Construction

local Storage = {}

function Storage.FindOrCreate(folders, config)
    local structures = folders.structures
    local existing = structures:FindFirstChild("ColonyStorage")
    if existing and existing:IsA("BasePart") then
        return existing
    end

    local storage = Instance.new("Part")
    storage.Name = "ColonyStorage"
    storage.Size = Vector3.new(8, 5, 8)
    storage.Anchored = true
    storage.Material = Enum.Material.WoodPlanks
    storage.Color = Color3.fromRGB(120, 86, 55)
    storage.Position = config.StoragePosition or Vector3.new(0, 2.5, 0)
    storage:SetAttribute("IsColonyStorage", true)
    storage.Parent = structures
    return storage
end

function Storage.GetDepositPosition(storage)
    return storage.Position + Vector3.new(0, 0, 5)
end

return Storage

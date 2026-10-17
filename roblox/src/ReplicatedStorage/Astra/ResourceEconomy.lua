local ResourceEconomy = {}

local RESOURCE_TYPES = {"Wood", "Stone", "Food", "Water"}

local function ensureAttributes(folder)
    for _, resourceType in ipairs(RESOURCE_TYPES) do
        local key = "Stock_" .. resourceType
        if folder:GetAttribute(key) == nil then
            folder:SetAttribute(key, 0)
        end
    end

    if folder:GetAttribute("StorageCapacity") == nil then
        folder:SetAttribute("StorageCapacity", 40)
    end
end

function ResourceEconomy.Ensure(worldStateFolder, capacity)
    ensureAttributes(worldStateFolder)
    if capacity then
        worldStateFolder:SetAttribute("StorageCapacity", capacity)
    end
    return worldStateFolder
end

function ResourceEconomy.Get(worldStateFolder, resourceType)
    return worldStateFolder:GetAttribute("Stock_" .. resourceType) or 0
end

function ResourceEconomy.GetTotal(worldStateFolder)
    local total = 0
    for _, resourceType in ipairs(RESOURCE_TYPES) do
        total += ResourceEconomy.Get(worldStateFolder, resourceType)
    end
    return total
end

function ResourceEconomy.GetFreeCapacity(worldStateFolder)
    local capacity = worldStateFolder:GetAttribute("StorageCapacity") or 40
    return math.max(0, capacity - ResourceEconomy.GetTotal(worldStateFolder))
end

function ResourceEconomy.Deposit(worldStateFolder, resourceType, amount)
    amount = math.max(0, amount or 0)
    local accepted = math.min(amount, ResourceEconomy.GetFreeCapacity(worldStateFolder))
    if accepted <= 0 then
        return 0
    end

    local key = "Stock_" .. resourceType
    worldStateFolder:SetAttribute(key, ResourceEconomy.Get(worldStateFolder, resourceType) + accepted)
    worldStateFolder:SetAttribute("StockTotal", ResourceEconomy.GetTotal(worldStateFolder))
    return accepted
end

function ResourceEconomy.CanAfford(worldStateFolder, recipe)
    for resourceType, amount in pairs(recipe or {}) do
        if ResourceEconomy.Get(worldStateFolder, resourceType) < amount then
            return false
        end
    end
    return true
end

function ResourceEconomy.Spend(worldStateFolder, recipe)
    if not ResourceEconomy.CanAfford(worldStateFolder, recipe) then
        return false
    end

    for resourceType, amount in pairs(recipe or {}) do
        local key = "Stock_" .. resourceType
        worldStateFolder:SetAttribute(key, ResourceEconomy.Get(worldStateFolder, resourceType) - amount)
    end

    worldStateFolder:SetAttribute("StockTotal", ResourceEconomy.GetTotal(worldStateFolder))
    return true
end

function ResourceEconomy.Types()
    return RESOURCE_TYPES
end

return ResourceEconomy

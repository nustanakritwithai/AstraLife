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
    if folder:GetAttribute("P3_RequestMode") == nil then
        folder:SetAttribute("P3_RequestMode", true)
    end
end

local function updateStockTotal(worldStateFolder)
    local total = 0
    for _, resourceType in ipairs(RESOURCE_TYPES) do
        total += worldStateFolder:GetAttribute("Stock_" .. resourceType) or 0
    end
    worldStateFolder:SetAttribute("StockTotal", total)
    return total
end

local function updateMaterialReady(worldStateFolder)
    local active = worldStateFolder:GetAttribute("ActiveBuildId")
    if not active or active == "None" then
        worldStateFolder:SetAttribute("P3_MaterialsReady", false)
        return false
    end

    for _, resourceType in ipairs(RESOURCE_TYPES) do
        local required = worldStateFolder:GetAttribute("P3_Required_" .. resourceType) or 0
        local delivered = worldStateFolder:GetAttribute("P3_Delivered_" .. resourceType) or 0
        if delivered < required then
            worldStateFolder:SetAttribute("P3_MaterialsReady", false)
            return false
        end
    end

    worldStateFolder:SetAttribute("P3_MaterialsReady", true)
    worldStateFolder:SetAttribute("P3_AllMaterialsDelivered", true)
    return true
end

function ResourceEconomy.Ensure(worldStateFolder, capacity)
    ensureAttributes(worldStateFolder)
    if capacity then
        worldStateFolder:SetAttribute("StorageCapacity", capacity)
    end
    updateStockTotal(worldStateFolder)
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

function ResourceEconomy.DepositToStorage(worldStateFolder, resourceType, amount)
    amount = math.max(0, amount or 0)
    local accepted = math.min(amount, ResourceEconomy.GetFreeCapacity(worldStateFolder))
    if accepted <= 0 then
        return 0
    end
    local key = "Stock_" .. resourceType
    worldStateFolder:SetAttribute(key, ResourceEconomy.Get(worldStateFolder, resourceType) + accepted)
    updateStockTotal(worldStateFolder)
    return accepted
end

-- Compatibility: P2 storage deposits only. P3 build delivery uses DeliverToBuildSite.
function ResourceEconomy.Deposit(worldStateFolder, resourceType, amount)
    return ResourceEconomy.DepositToStorage(worldStateFolder, resourceType, amount)
end

function ResourceEconomy.Consume(worldStateFolder, resourceType, amount)
    amount = math.max(0, amount or 0)
    local current = ResourceEconomy.Get(worldStateFolder, resourceType)
    local consumed = math.min(current, amount)
    if consumed <= 0 then
        return 0
    end
    worldStateFolder:SetAttribute("Stock_" .. resourceType, current - consumed)
    updateStockTotal(worldStateFolder)
    return consumed
end

function ResourceEconomy.GetBuildMissing(worldStateFolder, resourceType)
    local required = worldStateFolder:GetAttribute("P3_Required_" .. resourceType) or 0
    local delivered = worldStateFolder:GetAttribute("P3_Delivered_" .. resourceType) or 0
    return math.max(0, required - delivered)
end

function ResourceEconomy.IsRequestedForBuild(worldStateFolder, resourceType)
    local active = worldStateFolder:GetAttribute("ActiveBuildId")
    return active ~= nil
        and active ~= "None"
        and worldStateFolder:GetAttribute("P3_MaterialsReady") ~= true
        and ResourceEconomy.GetBuildMissing(worldStateFolder, resourceType) > 0
end

function ResourceEconomy.GetMostNeededBuildType(worldStateFolder)
    for _, resourceType in ipairs(RESOURCE_TYPES) do
        if ResourceEconomy.IsRequestedForBuild(worldStateFolder, resourceType) then
            return resourceType, ResourceEconomy.GetBuildMissing(worldStateFolder, resourceType)
        end
    end
    return nil, 0
end

function ResourceEconomy.DeliverToBuildSite(worldStateFolder, resourceType, amount)
    amount = math.max(0, amount or 0)
    if amount <= 0 or not ResourceEconomy.IsRequestedForBuild(worldStateFolder, resourceType) then
        return 0
    end

    local missing = ResourceEconomy.GetBuildMissing(worldStateFolder, resourceType)
    local accepted = math.min(amount, missing)
    if accepted <= 0 then
        return 0
    end

    local key = "P3_Delivered_" .. resourceType
    local delivered = worldStateFolder:GetAttribute(key) or 0
    worldStateFolder:SetAttribute(key, delivered + accepted)
    worldStateFolder:SetAttribute("P3_MaterialDelivered", true)
    worldStateFolder:SetAttribute("P3_PhysicalDelivery", true)
    worldStateFolder:SetAttribute("P3_LastDelivery", resourceType .. "+" .. tostring(accepted))
    worldStateFolder:SetAttribute("P3_LastDeliveryType", resourceType)
    updateMaterialReady(worldStateFolder)
    return accepted
end

function ResourceEconomy.CanAfford(worldStateFolder, recipe)
    if worldStateFolder:GetAttribute("P3_RequestMode") == true
        and (worldStateFolder:GetAttribute("ActiveBuildId") or "None") == "None"
    then
        return true
    end

    for resourceType, amount in pairs(recipe or {}) do
        if ResourceEconomy.Get(worldStateFolder, resourceType) < amount then
            return false
        end
    end
    return true
end

function ResourceEconomy.Spend(worldStateFolder, recipe)
    for resourceType, amount in pairs(recipe or {}) do
        if ResourceEconomy.Get(worldStateFolder, resourceType) < amount then
            return false
        end
    end
    for resourceType, amount in pairs(recipe or {}) do
        local key = "Stock_" .. resourceType
        worldStateFolder:SetAttribute(key, ResourceEconomy.Get(worldStateFolder, resourceType) - amount)
    end
    updateStockTotal(worldStateFolder)
    return true
end

function ResourceEconomy.BuildSiteReady(worldStateFolder)
    return updateMaterialReady(worldStateFolder)
end

function ResourceEconomy.Types()
    return RESOURCE_TYPES
end

return ResourceEconomy

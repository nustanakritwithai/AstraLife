local StationCatalog = {}

local stations = {
    Campfire = { tier = 0, inputSlots = 4, fuelSlots = 1, outputSlots = 4, queueSlots = 2, speedMultiplier = 1.0, fuelTags = {"fuel"}, capabilities = { cooking = true, carbonization = true } },
    Furnace = { tier = 1, inputSlots = 6, fuelSlots = 2, outputSlots = 6, queueSlots = 3, speedMultiplier = 1.0, fuelTags = {"fuel"}, capabilities = { smelting = true } },
    Workbench = { tier = 1, inputSlots = 12, fuelSlots = 0, outputSlots = 8, queueSlots = 4, speedMultiplier = 1.15, capabilities = { crafting = true, building = true, research = true } },
    Anvil = { tier = 2, inputSlots = 8, fuelSlots = 0, outputSlots = 6, queueSlots = 3, speedMultiplier = 1.2, capabilities = { metalworking = true, repair = true } },
}

function StationCatalog.Get(id) return stations[id] end
function StationCatalog.All() return stations end
function StationCatalog.Supports(id, capability)
    local station = stations[id]
    return station ~= nil and station.capabilities and station.capabilities[capability] == true
end
function StationCatalog.CanHostRecipe(id, requiredStation)
    if requiredStation == "hand" then return id == nil or id == "hand" end
    return stations[id] ~= nil and id == requiredStation
end

return StationCatalog

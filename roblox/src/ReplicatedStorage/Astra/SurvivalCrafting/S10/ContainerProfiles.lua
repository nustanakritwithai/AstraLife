local ContainerProfiles = {}

local profiles = {
    StorageBox = { bays = { storage = { slots = 24, accepts = "any" } } },
    Campfire = { bays = { input = { slots = 4, accepts = "food_raw" }, fuel = { slots = 1, accepts = "fuel" }, output = { slots = 4, accepts = "any" } } },
    Furnace = { bays = { input = { slots = 6, accepts = "ore" }, fuel = { slots = 2, accepts = "fuel" }, output = { slots = 6, accepts = "any" } } },
    Workbench = { bays = { input = { slots = 12, accepts = "any" }, output = { slots = 8, accepts = "any" } } },
    Anvil = { bays = { input = { slots = 8, accepts = "any" }, output = { slots = 6, accepts = "any" } } },
    Quarry = { bays = { fuel = { slots = 4, accepts = "fuel" }, output = { slots = 12, accepts = "ore" } } },
    Sawmill = { bays = { fuel = { slots = 4, accepts = "fuel" }, output = { slots = 12, accepts = "wood" } } },
}

function ContainerProfiles.Get(id) return profiles[id] end
function ContainerProfiles.All() return profiles end
return ContainerProfiles

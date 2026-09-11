local BiomeCatalog = {}

BiomeCatalog.Definitions = {
    Ocean = {
        terrain = "Water",
        walkable = false,
        fertility = 0.00,
        waterPotential = 1.00,
        vegetation = 0.00,
        food = 0.00,
        tags = { "aquatic", "deep-water" },
    },
    Shore = {
        terrain = "Sand",
        walkable = true,
        fertility = 0.20,
        waterPotential = 0.75,
        vegetation = 0.15,
        food = 0.10,
        tags = { "coast", "wet" },
    },
    Plains = {
        terrain = "Grass",
        walkable = true,
        fertility = 0.70,
        waterPotential = 0.35,
        vegetation = 0.60,
        food = 0.45,
        tags = { "open", "fertile" },
    },
    Forest = {
        terrain = "Ground",
        walkable = true,
        fertility = 0.90,
        waterPotential = 0.45,
        vegetation = 0.95,
        food = 0.70,
        tags = { "wooded", "fertile", "resource-rich" },
    },
    Wetland = {
        terrain = "Mud",
        walkable = true,
        fertility = 0.85,
        waterPotential = 0.90,
        vegetation = 0.80,
        food = 0.65,
        tags = { "wet", "soft-ground" },
    },
    Desert = {
        terrain = "Sand",
        walkable = true,
        fertility = 0.10,
        waterPotential = 0.08,
        vegetation = 0.08,
        food = 0.04,
        tags = { "dry", "exposed" },
    },
    Highland = {
        terrain = "Rock",
        walkable = true,
        fertility = 0.25,
        waterPotential = 0.20,
        vegetation = 0.20,
        food = 0.10,
        tags = { "highland", "rocky" },
    },
    Mountain = {
        terrain = "Rock",
        walkable = false,
        fertility = 0.05,
        waterPotential = 0.15,
        vegetation = 0.03,
        food = 0.00,
        tags = { "mountain", "steep", "blocked" },
    },
}

function BiomeCatalog.Get(name)
    return BiomeCatalog.Definitions[name] or BiomeCatalog.Definitions.Plains
end

function BiomeCatalog.Classify(sample)
    local elevation = sample.elevation or 0.5
    local moisture = sample.moisture or 0.5
    local temperature = sample.temperature or 0.5
    local slope = sample.slope or 0

    if elevation < 0.27 then
        return "Ocean"
    end
    if elevation < 0.33 then
        return "Shore"
    end
    if slope >= 0.68 or elevation >= 0.82 then
        return "Mountain"
    end
    if elevation >= 0.68 then
        return "Highland"
    end
    if moisture >= 0.76 and elevation < 0.52 then
        return "Wetland"
    end
    if moisture <= 0.24 and temperature >= 0.58 then
        return "Desert"
    end
    if moisture >= 0.52 then
        return "Forest"
    end
    return "Plains"
end

return BiomeCatalog

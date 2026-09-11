local EcosystemCatalog = {}

EcosystemCatalog.Definitions = {
    Ocean = {
        herbivoreCapacity = 0.00,
        predatorCapacity = 0.00,
        scavengerCapacity = 0.00,
        nutrientRetention = 0.20,
    },
    Shore = {
        herbivoreCapacity = 0.22,
        predatorCapacity = 0.04,
        scavengerCapacity = 0.12,
        nutrientRetention = 0.42,
    },
    Plains = {
        herbivoreCapacity = 1.00,
        predatorCapacity = 0.18,
        scavengerCapacity = 0.20,
        nutrientRetention = 0.68,
    },
    Forest = {
        herbivoreCapacity = 1.15,
        predatorCapacity = 0.24,
        scavengerCapacity = 0.28,
        nutrientRetention = 0.78,
    },
    Wetland = {
        herbivoreCapacity = 0.92,
        predatorCapacity = 0.20,
        scavengerCapacity = 0.32,
        nutrientRetention = 0.88,
    },
    Desert = {
        herbivoreCapacity = 0.18,
        predatorCapacity = 0.05,
        scavengerCapacity = 0.14,
        nutrientRetention = 0.28,
    },
    Highland = {
        herbivoreCapacity = 0.38,
        predatorCapacity = 0.10,
        scavengerCapacity = 0.16,
        nutrientRetention = 0.48,
    },
    Mountain = {
        herbivoreCapacity = 0.08,
        predatorCapacity = 0.02,
        scavengerCapacity = 0.08,
        nutrientRetention = 0.25,
    },
}

function EcosystemCatalog.Get(biomeName)
    return EcosystemCatalog.Definitions[biomeName] or EcosystemCatalog.Definitions.Plains
end

return EcosystemCatalog

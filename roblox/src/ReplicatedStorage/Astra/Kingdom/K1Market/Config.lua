local Config = {}

Config.SchemaVersion = "K1.1"
Config.PriceSmoothingAlpha = 0.30
Config.MinScarcity = 0.25
Config.MaxScarcity = 6.00
Config.MinPriceMultiplier = 0.30
Config.MaxPriceMultiplier = 6.00

Config.Resources = {
    Wood = {
        basePrice = 5,
        perCapitaDemand = 0.22,
        criticalDemand = 0.00,
        infrastructureDemand = 0.22,
    },
    Stone = {
        basePrice = 7,
        perCapitaDemand = 0.16,
        criticalDemand = 0.00,
        infrastructureDemand = 0.28,
    },
    Food = {
        basePrice = 4,
        perCapitaDemand = 0.90,
        criticalDemand = 2.75,
        infrastructureDemand = 0.00,
    },
    Water = {
        basePrice = 3,
        perCapitaDemand = 0.95,
        criticalDemand = 3.00,
        infrastructureDemand = 0.00,
    },
}

return Config

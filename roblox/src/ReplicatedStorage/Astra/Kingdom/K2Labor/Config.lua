local Config = {}

Config.SchemaVersion = "K2.1"
Config.SmoothingAlpha = 0.30
Config.MinWagePremium = 1.00
Config.MaxWagePremium = 1.80

Config.Professions = {
    farmer = {
        resource = "Food",
        healthyPerCapita = 3.0,
        baseDemandWeight = 1.00,
    },
    woodcutter = {
        resource = "Wood",
        healthyPerCapita = 2.5,
        baseDemandWeight = 0.80,
    },
    miner = {
        resource = "Stone",
        healthyPerCapita = 2.0,
        baseDemandWeight = 0.75,
    },
    crafter = {
        resource = "Stone",
        secondaryResource = "Wood",
        healthyPerCapita = 2.0,
        baseDemandWeight = 0.70,
    },
}

return Config

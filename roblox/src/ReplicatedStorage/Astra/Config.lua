local Config = {}

Config.RuntimeVersion = "0.3.0-p3"

Config.TickSeconds = 2
Config.ThinkVisibleSeconds = 2

Config.PerceptionRange = 55
Config.ResourceRange = 25
Config.AgentRange = 40
Config.ThreatRange = 30
Config.CommunicationRange = 45
Config.CollectDistance = 4.5
Config.ArrivalDistance = 5
Config.DepositDistance = 6
Config.BuildSiteDeliveryDistance = 6

Config.WalkSpeed = 9
Config.RunSpeed = 14
Config.StuckDistanceEpsilon = 0.75
Config.StuckTicksBeforePath = 3

Config.ShortMemoryLimit = 40
Config.LongMemoryLimit = 120
Config.BeliefDecayAfterTicks = 6
Config.BeliefDecayPerTick = 0.03

Config.MessageTTL = 8
Config.SharedKnowledgeTTL = 12
Config.ReportedResourceConfidence = 0.75
Config.DirectObservationConfidence = 1.0
Config.MaxMessageQueueSize = 50

Config.EnergyStart = 100
Config.EnergyDecayPerTick = 1.2
Config.EnergyRestGain = 9
Config.EnergyLow = 28
Config.SafetyStart = 100
Config.SocialStart = 60

Config.ResourceRespawnSeconds = 14
Config.DemoResourceCount = 8
Config.CreateDemoResources = true
Config.CreateDemoAgents = true

Config.CarryCapacity = 3
Config.StorageCapacity = 40
Config.StoragePosition = Vector3.new(0, 2.5, 0)

Config.P3RequestMode = true
Config.BuildSiteMarkerTransparency = 0.55

Config.ResourceTypes = {
    Wood = { color = Color3.fromRGB(121, 85, 58), material = Enum.Material.Wood, yield = 1 },
    Stone = { color = Color3.fromRGB(130, 135, 145), material = Enum.Material.Slate, yield = 1 },
    Food = { color = Color3.fromRGB(92, 200, 92), material = Enum.Material.Grass, yield = 1 },
    Water = { color = Color3.fromRGB(70, 145, 255), material = Enum.Material.Glass, yield = 1 },
}

Config.Roles = {
    Scout = "Scout",
    Gatherer = "Gatherer",
    Builder = "Builder",
    Explorer = "Explorer",
}

Config.Blueprints = {
    {
        id = "Campfire",
        displayName = "Campfire",
        recipe = { Wood = 2, Stone = 1 },
        buildSteps = 3,
        offset = Vector3.new(8, 0, 8),
    },
    {
        id = "Shelter",
        displayName = "Shelter",
        recipe = { Wood = 4, Stone = 2 },
        buildSteps = 4,
        offset = Vector3.new(-10, 0, 10),
    },
    {
        id = "Storage",
        displayName = "Storage",
        recipe = { Wood = 4, Stone = 3 },
        buildSteps = 4,
        offset = Vector3.new(12, 0, -10),
    },
    {
        id = "WatchTower",
        displayName = "Watch Tower",
        recipe = { Wood = 6, Stone = 4 },
        buildSteps = 5,
        offset = Vector3.new(-14, 0, -12),
    },
}

return Config

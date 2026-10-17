local Config = {}

Config.TickSeconds = 2
Config.ThinkVisibleSeconds = 2

Config.PerceptionRange = 55
Config.ResourceRange = 55
Config.AgentRange = 40
Config.ThreatRange = 30
Config.CommunicationRange = 35
Config.CollectDistance = 4.5
Config.ArrivalDistance = 5

Config.WalkSpeed = 9
Config.RunSpeed = 14
Config.StuckDistanceEpsilon = 0.75
Config.StuckTicksBeforePath = 3

Config.ShortMemoryLimit = 40
Config.LongMemoryLimit = 120
Config.BeliefDecayAfterTicks = 6
Config.BeliefDecayPerTick = 0.03

Config.EnergyStart = 100
Config.EnergyDecayPerTick = 1.2
Config.EnergyRestGain = 9
Config.EnergyLow = 28
Config.SafetyStart = 100
Config.SocialStart = 60

Config.ResourceRespawnSeconds = 12
Config.DemoResourceCount = 7
Config.CreateDemoResources = true
Config.CreateDemoAgents = true

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
        cost = 2,
        buildSteps = 3,
        offset = Vector3.new(8, 0, 8),
    },
    {
        id = "Shelter",
        displayName = "Shelter",
        cost = 4,
        buildSteps = 4,
        offset = Vector3.new(-10, 0, 10),
    },
    {
        id = "Storage",
        displayName = "Storage",
        cost = 5,
        buildSteps = 4,
        offset = Vector3.new(12, 0, -10),
    },
    {
        id = "WatchTower",
        displayName = "Watch Tower",
        cost = 7,
        buildSteps = 5,
        offset = Vector3.new(-14, 0, -12),
    },
}

return Config

local Config = {}

Config.RuntimeVersion = "0.7.5-w7-integration"

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
Config.SurvivalUseDistance = 6
Config.SocialDistance = 8

Config.WalkSpeed = 9
Config.RunSpeed = 14
Config.StuckDistanceEpsilon = 0.75
Config.StuckTicksBeforePath = 3
Config.PathRecomputeIntervalTicks = 2
Config.PathTargetChangeDistance = 4

Config.ShortMemoryLimit = 40
Config.LongMemoryLimit = 120
Config.BeliefDecayAfterTicks = 6
Config.BeliefDecayPerTick = 0.03

Config.MessageTTL = 8
Config.SharedKnowledgeTTL = 12
Config.ReportedResourceConfidence = 0.75
Config.DirectObservationConfidence = 1.0
Config.MaxMessageQueueSize = 50
Config.MessageRegistryTTL = 24
Config.MessageRegistryCleanupIntervalTicks = 6

-- P4 survival needs: 100 = fully satisfied, 0 = critical.
Config.HungerStart = 85
Config.HungerDecayPerTick = 2.5
Config.HungerLow = 45
Config.HungerCritical = 15
Config.FoodRestore = 55
Config.ThirstStart = 85
Config.ThirstDecayPerTick = 3.5
Config.ThirstLow = 45
Config.ThirstCritical = 15
Config.WaterRestore = 60
Config.EnergyStart = 55
Config.EnergyDecayPerTick = 2.0
Config.EnergyRestGain = 16
Config.EnergyLow = 30
Config.ShelterRestBonus = 8
Config.SafetyStart = 100
Config.SafetyRecoveryPerTick = 3
Config.SafetyThreatLoss = 15
Config.SocialStart = 55
Config.SocialDecayPerTick = 1.5
Config.SocialLow = 28
Config.SocialRestore = 35
Config.CriticalNeedDamage = 4
Config.HealthyRecovery = 1
Config.SurvivalStockTargetFood = 10
Config.SurvivalStockTargetWater = 10
Config.DemoStartingFood = 24
Config.DemoStartingWater = 24

-- Legacy P5 fallback values. When W2 is online, climate authority comes from AstraLivingWorldState.
Config.DayLengthTicks = 24
Config.DawnEndTick = 3
Config.DayEndTick = 12
Config.DuskEndTick = 15
Config.WeatherPeriodTicks = 6
Config.WeatherSequence = {"Clear", "Rain", "Clear", "Storm"}
Config.RainThirstDecayMultiplier = 0.75
Config.NightEnergyDecayMultiplier = 1.20
Config.StormEnergyDecayMultiplier = 1.35
Config.StormSafetyLossPerTick = 5
Config.WorldResourceGrowthInterval = 3
Config.WorldResourceMaxBonusNodes = 10
Config.ThreatDurationTicks = 6
Config.DangerZonePosition = Vector3.new(18, 1, 2)
Config.DangerZoneSize = Vector3.new(18, 1, 18)
Config.EnvironmentShelterAtNight = true
Config.EnvironmentShelterInStorm = true

-- P6 emergent role selection.
Config.RoleEvaluationIntervalTicks = 4
Config.RoleMinDurationTicks = 10
Config.RoleSwitchMargin = 14
Config.RoleCoverageBonus = 42
Config.RoleInertiaBonus = 10
Config.RoleInitialHintBonus = 30
Config.RoleSkillWeight = 1.15
Config.RoleTraitWeight = 0.75
Config.RoleExperienceScout = 0
Config.RoleExperienceGatherer = 0
Config.RoleExperienceBuilder = 0
Config.RoleExperienceSurvival = 0

-- P7 outcome-based skill learning.
Config.P7OutcomeLearningEnabled = true
Config.P7SkillCap = 100
Config.P7XPToSkillScale = 3.0
Config.P7AntiGrindWindowTicks = 6
Config.P7AntiGrindRepeatPenalty = 0.55
Config.P7MinimumRewardMultiplier = 0.2
Config.P7ScoutObservationXP = 1.0
Config.P7GatherCollectXP = 1.6
Config.P7GatherDepositXP = 1.2
Config.P7BuilderProgressXP = 1.4
Config.P7BuilderCompleteXP = 4.0
Config.P7SurvivalRecoveryXP = 0.9
Config.P7FailureLearningXP = 0.35
Config.P7ScoutRangePerSkill = 0.004
Config.P7GatherRangePerSkill = 0.0025
Config.P7BuildSpeedPerSkill = 0.01
Config.P7SurvivalDecayReductionPerSkill = 0.003
Config.P7MaxResourceRangeMultiplier = 1.45
Config.P7MaxBuildSpeedMultiplier = 1.75
Config.P7MinSurvivalDecayMultiplier = 0.70

-- P7.5 12-agent scale/integration test.
Config.ScaleAgentCount = 12
Config.ScaleResourceNodeCount = 24
Config.DecisionStaggerStepSeconds = 0.14
Config.ScaleRoleTargets = { Scout = 2, Gatherer = 7, Builder = 3 }
Config.ScaleRoleGapBonus = 9
Config.ScaleRoleOverTargetPenalty = 3
Config.ScaleVerifierMinTicks = 30
Config.ScaleLongRunTicks = 500
Config.ScaleMaxStuckAgents = 3
Config.ScaleMaxMessageRegistry = 900
Config.ScaleRoleTolerance = 2

-- W7 integration compatibility.
Config.W7IntegrationEnabled = true
Config.LivingWorldDecisionTicks = 8 -- 8 * 0.25s = 2s, matching the legacy Agent cadence.

-- I0.1 world danger -> Agent survival bridge.
Config.WorldDangerFleeThreshold = 0.5 -- effective W4/W7 cell danger that forces Flee
Config.WorldDangerSafetyLossPerTick = 8 -- safety loss per tick at danger == 1
Config.WorldEscapeRadiusCells = 10 -- search radius for the nearest safe cell

-- I0.4 reachable-source fallback.
Config.W6RouteAttemptBudget = 3 -- max W5 route attempts per Navigate call

-- I0.3 runtime integration verifier.
Config.IntegrationTransactionGraceTicks = 200 -- living ticks before W6 transactions are required
Config.LivingWorldPhysicalSize = 1056 -- covers the 64x64 * 16-stud logical world with a small margin.

Config.ResourceRespawnSeconds = 14
Config.DemoResourceCount = 24
Config.CreateDemoResources = true
Config.CreateDemoAgents = true

Config.CarryCapacity = 3
Config.StorageCapacity = 120
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
    { id = "Campfire", displayName = "Campfire", recipe = { Wood = 2, Stone = 1 }, buildSteps = 3, offset = Vector3.new(8, 0, 8) },
    { id = "Shelter", displayName = "Shelter", recipe = { Wood = 4, Stone = 2 }, buildSteps = 4, offset = Vector3.new(-10, 0, 10) },
    { id = "Storage", displayName = "Storage", recipe = { Wood = 4, Stone = 3 }, buildSteps = 4, offset = Vector3.new(12, 0, -10) },
    { id = "WatchTower", displayName = "Watch Tower", recipe = { Wood = 6, Stone = 4 }, buildSteps = 5, offset = Vector3.new(-14, 0, -12) },
}

return Config

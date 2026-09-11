local SkillLearning = {}

local SKILLS = {"Scout", "Gatherer", "Builder", "Survival"}
local profiles = setmetatable({}, { __mode = "k" })
local buildSnapshot = {
    buildId = nil,
    progress = 0,
    completedBlueprint = nil,
    worker = nil,
}

local function clampSkill(value, config)
    return math.clamp(value or 0, 0, config.P7SkillCap or 100)
end

local function levelFor(skill)
    if skill >= 100 then return 5 end
    return math.clamp(math.floor((skill or 0) / 25) + 1, 1, 5)
end

local function ensureProfile(agent, config)
    local profile = profiles[agent]
    if profile then return profile end

    profile = {
        base = {},
        seen = {},
        repeats = {},
        snapshot = {
            discoveryCount = agent:GetAttribute("P7DiscoveryCount") or 0,
            carry = agent:GetAttribute("CarryTotal") or 0,
            hunger = agent:GetAttribute("Hunger") or config.HungerStart,
            thirst = agent:GetAttribute("Thirst") or config.ThirstStart,
            energy = agent:GetAttribute("Energy") or config.EnergyStart,
            social = agent:GetAttribute("Social") or config.SocialStart,
            stuck = agent:GetAttribute("StuckTicks") or 0,
        },
    }

    for _, skill in ipairs(SKILLS) do
        local current = agent:GetAttribute("Skill_" .. skill) or 0
        profile.base[skill] = current
        if agent:GetAttribute("P7_BaseSkill_" .. skill) == nil then
            agent:SetAttribute("P7_BaseSkill_" .. skill, current)
        end
        if agent:GetAttribute("P7_XP_" .. skill) == nil then
            agent:SetAttribute("P7_XP_" .. skill, 0)
        end
    end

    profiles[agent] = profile
    agent:SetAttribute("P7LearningReady", true)
    agent:SetAttribute("P7LastLearningEvent", "None")
    agent:SetAttribute("P7LastLearningReward", 0)
    agent:SetAttribute("P7AntiGrindMultiplier", 1)
    return profile
end

local function recomputeSkill(agent, skill, config)
    local base = agent:GetAttribute("P7_BaseSkill_" .. skill) or 0
    local xp = agent:GetAttribute("P7_XP_" .. skill) or 0
    local learned = math.sqrt(math.max(0, xp)) * (config.P7XPToSkillScale or 3)
    local value = clampSkill(base + learned, config)
    agent:SetAttribute("Skill_" .. skill, value)
    agent:SetAttribute("Level_" .. skill, levelFor(value))
    return value
end

local function applyEffects(agent, config)
    local role = agent:GetAttribute("Role")
    local scout = recomputeSkill(agent, "Scout", config)
    local gatherer = recomputeSkill(agent, "Gatherer", config)
    local builder = recomputeSkill(agent, "Builder", config)
    local survival = recomputeSkill(agent, "Survival", config)

    local resourceRangeMultiplier = 1
    if role == config.Roles.Scout then
        resourceRangeMultiplier = 1 + scout * (config.P7ScoutRangePerSkill or 0)
    elseif role == config.Roles.Gatherer then
        resourceRangeMultiplier = 1 + gatherer * (config.P7GatherRangePerSkill or 0)
    end
    resourceRangeMultiplier = math.min(config.P7MaxResourceRangeMultiplier or 1.45, resourceRangeMultiplier)

    local buildMultiplier = math.min(
        config.P7MaxBuildSpeedMultiplier or 1.75,
        1 + builder * (config.P7BuildSpeedPerSkill or 0)
    )
    local survivalDecay = math.max(
        config.P7MinSurvivalDecayMultiplier or 0.70,
        1 - survival * (config.P7SurvivalDecayReductionPerSkill or 0)
    )

    agent:SetAttribute("P7_ResourceRangeMultiplier", resourceRangeMultiplier)
    agent:SetAttribute("P7_BuildSpeedMultiplier", buildMultiplier)
    agent:SetAttribute("P7_SurvivalDecayMultiplier", survivalDecay)
    agent:SetAttribute("P7_EffectsReady", true)
end

local function rewardMultiplier(profile, category, tick, config)
    local previous = profile.repeats[category]
    local count = 0
    if previous and tick - previous.tick <= (config.P7AntiGrindWindowTicks or 6) then
        count = previous.count + 1
    end
    profile.repeats[category] = { tick = tick, count = count }

    local multiplier = (config.P7AntiGrindRepeatPenalty or 0.55) ^ count
    multiplier = math.max(config.P7MinimumRewardMultiplier or 0.2, multiplier)
    return multiplier, count
end

local function grant(agent, skill, amount, category, eventId, tick, config, worldState)
    if amount <= 0 then return 0 end

    local profile = ensureProfile(agent, config)
    if eventId and profile.seen[eventId] then return 0 end
    if eventId then profile.seen[eventId] = true end

    local multiplier, repeatCount = rewardMultiplier(profile, category, tick, config)
    local reward = amount * multiplier
    local key = "P7_XP_" .. skill
    agent:SetAttribute(key, (agent:GetAttribute(key) or 0) + reward)
    agent:SetAttribute("P7_XP_Total", (agent:GetAttribute("P7_XP_Total") or 0) + reward)
    agent:SetAttribute("P7LastLearningEvent", category)
    agent:SetAttribute("P7LastLearningReward", reward)
    agent:SetAttribute("P7AntiGrindMultiplier", multiplier)

    worldState:SetAttribute("P7_XPRecorded", true)
    worldState:SetAttribute("P7_OutcomeLearningObserved", true)
    worldState:SetAttribute("P6_SkillUpdated", true)
    if repeatCount > 0 then worldState:SetAttribute("P7_AntiGrindObserved", true) end

    recomputeSkill(agent, skill, config)
    worldState:SetAttribute("P7_SkillRecomputed", true)
    return reward
end

local function processAgent(agent, folders, tick, config)
    if not agent:IsA("Model") then return end

    local profile = ensureProfile(agent, config)
    local snap = profile.snapshot
    local state = folders.state

    -- Scout XP now tracks first-time resource discoveries instead of observation IDs.
    -- Observation IDs contain tick data, so using them directly allowed passive XP farming.
    local discoveryCount = agent:GetAttribute("P7DiscoveryCount") or 0
    if discoveryCount > snap.discoveryCount then
        local delta = discoveryCount - snap.discoveryCount
        grant(
            agent,
            "Scout",
            delta * (config.P7ScoutObservationXP or 1),
            "scout_discovery",
            nil,
            tick,
            config,
            state
        )
        state:SetAttribute("P7_UniqueDiscoveryLearning", true)
    end

    local carry = agent:GetAttribute("CarryTotal") or 0
    if carry > snap.carry then
        grant(agent, "Gatherer", (carry - snap.carry) * (config.P7GatherCollectXP or 1.6), "gather_collect", nil, tick, config, state)
    elseif carry < snap.carry then
        local goal = agent:GetAttribute("Goal") or ""
        if goal == "DepositResources" or goal == "DeliverMaterials" then
            grant(agent, "Gatherer", (snap.carry - carry) * (config.P7GatherDepositXP or 1.2), "gather_delivery", nil, tick, config, state)
        end
    end

    local hunger = agent:GetAttribute("Hunger") or snap.hunger
    local thirst = agent:GetAttribute("Thirst") or snap.thirst
    local energy = agent:GetAttribute("Energy") or snap.energy
    local social = agent:GetAttribute("Social") or snap.social
    local recovered = 0
    if hunger > snap.hunger + 2 then recovered += 1 end
    if thirst > snap.thirst + 2 then recovered += 1 end
    if energy > snap.energy + 2 then recovered += 1 end
    if social > snap.social + 2 then recovered += 1 end
    if recovered > 0 then
        grant(agent, "Survival", recovered * (config.P7SurvivalRecoveryXP or 0.9), "survival_recovery", nil, tick, config, state)
    end

    local stuck = agent:GetAttribute("StuckTicks") or 0
    if stuck >= config.StuckTicksBeforePath and snap.stuck < config.StuckTicksBeforePath then
        local role = agent:GetAttribute("Role") or config.Roles.Scout
        local skill = role == config.Roles.Builder and "Builder"
            or role == config.Roles.Gatherer and "Gatherer"
            or "Scout"
        grant(agent, skill, config.P7FailureLearningXP or 0.35, "failure_recovery", nil, tick, config, state)
        state:SetAttribute("P7_FailureLearningObserved", true)
    end

    snap.discoveryCount = discoveryCount
    snap.carry = carry
    snap.hunger = hunger
    snap.thirst = thirst
    snap.energy = energy
    snap.social = social
    snap.stuck = stuck

    applyEffects(agent, config)
end

local function processBuildOutcome(folders, tick, config)
    local state = folders.state
    local buildId = state:GetAttribute("P3_BuildId")
    local progress = state:GetAttribute("BuildProgress") or 0
    local workerName = state:GetAttribute("ActiveBuildWorker")
    local completedBlueprint = state:GetAttribute("P3_LastCompletedBlueprint")

    if buildId ~= buildSnapshot.buildId then
        buildSnapshot.buildId = buildId
        buildSnapshot.progress = 0
        if workerName and workerName ~= "None" then buildSnapshot.worker = workerName end
    end

    if progress > buildSnapshot.progress then
        local worker = workerName and workerName ~= "None" and folders.agents:FindFirstChild(workerName)
        if not worker and buildSnapshot.worker then worker = folders.agents:FindFirstChild(buildSnapshot.worker) end
        if worker then
            grant(worker, "Builder", config.P7BuilderProgressXP or 1.4, "builder_progress", nil, tick, config, state)
        end
    end

    if completedBlueprint and completedBlueprint ~= buildSnapshot.completedBlueprint then
        local worker = buildSnapshot.worker and folders.agents:FindFirstChild(buildSnapshot.worker) or nil
        if not worker and workerName and workerName ~= "None" then worker = folders.agents:FindFirstChild(workerName) end
        if worker then
            grant(worker, "Builder", config.P7BuilderCompleteXP or 4, "builder_complete", "build:" .. completedBlueprint, tick, config, state)
            state:SetAttribute("P7_BuildCompletionLearned", true)
        end
    end

    buildSnapshot.progress = progress
    buildSnapshot.completedBlueprint = completedBlueprint
    if workerName and workerName ~= "None" then buildSnapshot.worker = workerName end
end

function SkillLearning.PrepareAgent(agent, config)
    ensureProfile(agent, config)
    applyEffects(agent, config)
end

function SkillLearning.Initialize(folders, config)
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then SkillLearning.PrepareAgent(agent, config) end
    end
    buildSnapshot.buildId = folders.state:GetAttribute("P3_BuildId")
    buildSnapshot.progress = folders.state:GetAttribute("BuildProgress") or 0
    buildSnapshot.completedBlueprint = folders.state:GetAttribute("P3_LastCompletedBlueprint")
    buildSnapshot.worker = folders.state:GetAttribute("ActiveBuildWorker")
    folders.state:SetAttribute("P7_LearningInitialized", true)
    folders.state:SetAttribute("P7_AntiGrindReady", true)
end

function SkillLearning.Tick(folders, tick, config)
    for _, agent in ipairs(folders.agents:GetChildren()) do processAgent(agent, folders, tick, config) end
    processBuildOutcome(folders, tick, config)
    folders.state:SetAttribute("P7_EffectApplied", true)
end

function SkillLearning.SyncAll(folders, config)
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            ensureProfile(agent, config)
            applyEffects(agent, config)
        end
    end
end

return SkillLearning

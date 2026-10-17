local RoleSystem = {}

local ROLE_ORDER = {"Scout", "Gatherer", "Builder"}

local function clamp100(value)
    return math.clamp(value or 0, 0, 100)
end

local function nameSeed(name)
    local seed = 17
    for i = 1, #name do
        seed = (seed * 31 + string.byte(name, i)) % 10007
    end
    return seed
end

local function ensureAgentProfile(agent, config)
    if agent:GetAttribute("P6ProfileReady") == true then return end

    local hint = agent:GetAttribute("Role") or config.Roles.Explorer
    agent:SetAttribute("InitialRoleHint", hint)

    local seed = nameSeed(agent.Name)
    agent:SetAttribute("TraitCuriosity", 10 + (seed % 16))
    agent:SetAttribute("TraitIndustry", 10 + (math.floor(seed / 7) % 16))
    agent:SetAttribute("TraitCraft", 10 + (math.floor(seed / 13) % 16))

    agent:SetAttribute("Skill_Scout", hint == config.Roles.Scout and 12 or 6)
    agent:SetAttribute("Skill_Gatherer", hint == config.Roles.Gatherer and 12 or 6)
    agent:SetAttribute("Skill_Builder", hint == config.Roles.Builder and 12 or 6)
    agent:SetAttribute("Skill_Survival", 6)
    agent:SetAttribute("RoleExperienceTotal", 0)
    agent:SetAttribute("RoleSinceTick", 0)
    agent:SetAttribute("RoleSwitchCount", 0)
    -- Do not mark RoleAssignedBy here. Spawned agents must still receive one
    -- actual emergent-role decision in PrepareAgent.
    agent:SetAttribute("P6ProfileReady", true)
end

local function countRoles(agentsFolder, excludeAgent)
    local counts = {Scout = 0, Gatherer = 0, Builder = 0}
    for _, other in ipairs(agentsFolder:GetChildren()) do
        if other:IsA("Model") and other ~= excludeAgent then
            local role = other:GetAttribute("Role")
            if counts[role] ~= nil then counts[role] += 1 end
        end
    end
    return counts
end

local function syncRoleCounts(folders, config)
    local counts = countRoles(folders.agents, nil)
    local targetHealthy = true
    for _, role in ipairs(ROLE_ORDER) do
        folders.state:SetAttribute("ScaleRoleCount_" .. role, counts[role])
        local targets = config.ScaleRoleTargets
        local target = targets and targets[role]
        if target then
            folders.state:SetAttribute("ScaleRoleTarget_" .. role, target)
            if math.abs(counts[role] - target) > (config.ScaleRoleTolerance or 2) then
                targetHealthy = false
            end
        end
    end
    folders.state:SetAttribute("ScaleRoleTargetHealthy", targetHealthy)
    return counts, targetHealthy
end

local function buildMissing(worldState)
    local total = 0
    for _, resourceType in ipairs({"Wood", "Stone", "Food", "Water"}) do
        local required = worldState:GetAttribute("P3_Required_" .. resourceType) or 0
        local delivered = worldState:GetAttribute("P3_Delivered_" .. resourceType) or 0
        total += math.max(0, required - delivered)
    end
    return total
end

local function unfinishedStructures(folders, config)
    local count = 0
    for _, blueprint in ipairs(config.Blueprints) do
        if not folders.structures:FindFirstChild(blueprint.id) then count += 1 end
    end
    return count
end

local function demandFor(role, folders, config)
    local state = folders.state
    if role == config.Roles.Scout then
        local known = state:GetAttribute("KnownResourceCount") or 0
        local event = state:GetAttribute("WorldEvent") or "None"
        return 12 + (known < 8 and 22 or 4) + (event ~= "None" and 12 or 0)
    elseif role == config.Roles.Gatherer then
        local missing = math.min(30, buildMissing(state) * 5)
        local food = state:GetAttribute("Stock_Food") or 0
        local water = state:GetAttribute("Stock_Water") or 0
        local survival = (food < config.SurvivalStockTargetFood and 12 or 0)
            + (water < config.SurvivalStockTargetWater and 12 or 0)
        return 15 + missing + survival
    elseif role == config.Roles.Builder then
        local buildStatus = state:GetAttribute("BuildStatus") or "Idle"
        local active = state:GetAttribute("ActiveBuildId") or "None"
        if active ~= "None" or buildStatus ~= "Idle" then return 45 end
        return unfinishedStructures(folders, config) > 0 and 28 or 4
    end
    return 0
end

local function roleSkill(agent, role)
    return agent:GetAttribute("Skill_" .. role) or 0
end

local function traitScore(agent, role)
    if role == "Scout" then return agent:GetAttribute("TraitCuriosity") or 0 end
    if role == "Gatherer" then return agent:GetAttribute("TraitIndustry") or 0 end
    if role == "Builder" then return agent:GetAttribute("TraitCraft") or 0 end
    return 0
end

local function distributionScore(role, counts, config)
    local targets = config.ScaleRoleTargets
    if not targets or not targets[role] then
        return counts[role] == 0 and config.RoleCoverageBonus or 0
    end

    local target = targets[role]
    local projected = counts[role] + 1
    local missingBeforeAssignment = math.max(0, target - counts[role])
    local overAfterAssignment = math.max(0, projected - target)

    local score = missingBeforeAssignment * (config.ScaleRoleGapBonus or 9)
    score -= overAfterAssignment * (config.ScaleRoleOverTargetPenalty or 3)
    if counts[role] == 0 then score += config.RoleCoverageBonus end
    return score
end

local function scoreRole(agent, role, folders, config, currentRole, includeHint)
    local counts = countRoles(folders.agents, agent)
    local distribution = distributionScore(role, counts, config)
    local inertia = currentRole == role and config.RoleInertiaBonus or 0
    local hint = includeHint and agent:GetAttribute("InitialRoleHint") == role and config.RoleInitialHintBonus or 0
    local skill = roleSkill(agent, role) * config.RoleSkillWeight
    local trait = traitScore(agent, role) * config.RoleTraitWeight
    local demand = demandFor(role, folders, config)
    return skill + trait + demand + distribution + inertia + hint
end

local function chooseRole(agent, folders, config, currentRole, includeHint)
    local bestRole, bestScore = config.Roles.Scout, -math.huge
    local scores = {}
    for _, role in ipairs(ROLE_ORDER) do
        local score = scoreRole(agent, role, folders, config, currentRole, includeHint)
        scores[role] = score
        agent:SetAttribute("RoleScore_" .. role, math.floor(score * 10) / 10)
        if score > bestScore then bestRole, bestScore = role, score end
    end
    return bestRole, bestScore, scores
end

local function isRoleLocked(agent, folders, config)
    local role = agent:GetAttribute("Role")
    if role == config.Roles.Gatherer and (agent:GetAttribute("CarryTotal") or 0) > 0 then
        return true, "carrying_resources"
    end
    if role == config.Roles.Builder then
        local worker = folders.state:GetAttribute("ActiveBuildWorker")
        local status = folders.state:GetAttribute("BuildStatus") or "Idle"
        if worker == agent.Name and status ~= "Idle" then return true, "active_build" end
    end
    return false, nil
end

local function assignRole(agent, role, score, tick, reason, worldState)
    local previous = agent:GetAttribute("Role")
    agent:SetAttribute("PreviousRole", previous or "None")
    agent:SetAttribute("Role", role)
    agent:SetAttribute("RoleSinceTick", tick)
    agent:SetAttribute("RoleAssignedBy", "EmergentRoleSystem")
    agent:SetAttribute("P6RoleInitialized", true)
    agent:SetAttribute("RoleDecisionScore", math.floor(score * 10) / 10)
    agent:SetAttribute("RoleDecisionReason", reason)
    agent:SetAttribute("LastRoleEvaluationTick", tick)
    if previous and previous ~= role and previous ~= "Unassigned" then
        agent:SetAttribute("RoleSwitchCount", (agent:GetAttribute("RoleSwitchCount") or 0) + 1)
        worldState:SetAttribute("P6_RoleChanged", true)
        worldState:SetAttribute("P6_LastRoleChange", agent.Name .. ":" .. previous .. "->" .. role)
    end
end

local function gain(agent, skillName, amount)
    local key = "Skill_" .. skillName
    local before = agent:GetAttribute(key) or 0
    local after = clamp100(before + amount)
    agent:SetAttribute(key, after)
    return after > before
end

local function recordExperience(agent, worldState, config)
    local goal = agent:GetAttribute("Goal") or ""
    local updated = false
    if goal == "Explore" or goal == "Communicate" then
        updated = gain(agent, "Scout", config.RoleExperienceScout) or updated
    elseif goal == "GatherResource" or goal == "DepositResources" or goal == "DeliverMaterials" then
        updated = gain(agent, "Gatherer", config.RoleExperienceGatherer) or updated
    elseif goal == "BuildStructure" then
        updated = gain(agent, "Builder", config.RoleExperienceBuilder) or updated
    elseif goal == "Eat" or goal == "Drink" or goal == "Rest" or goal == "Socialize" or goal == "Flee" or goal == "SeekShelter" then
        updated = gain(agent, "Survival", config.RoleExperienceSurvival) or updated
    end

    if updated then
        agent:SetAttribute("RoleExperienceTotal", (agent:GetAttribute("RoleExperienceTotal") or 0) + 1)
        worldState:SetAttribute("P6_SkillUpdated", true)
    end
end

local function coverageBalanced(agentsFolder, config)
    local counts = countRoles(agentsFolder, nil)
    return counts[config.Roles.Scout] >= 1
        and counts[config.Roles.Gatherer] >= 1
        and counts[config.Roles.Builder] >= 1
end

function RoleSystem.PrepareAgent(agent, folders, config, tick)
    if not agent or not agent:IsA("Model") then return nil end
    ensureAgentProfile(agent, config)

    if agent:GetAttribute("P6RoleInitialized") ~= true
        or agent:GetAttribute("Role") == nil
        or agent:GetAttribute("Role") == "Unassigned"
    then
        local bestRole, bestScore = chooseRole(agent, folders, config, nil, true)
        assignRole(agent, bestRole, bestScore, tick or 0, "spawn_emergent_assignment", folders.state)
        folders.state:SetAttribute("P6_InitialAssignment", true)
        folders.state:SetAttribute("P6_RoleEvaluated", true)
        folders.state:SetAttribute("P6_RoleDecisionRecorded", true)
    end

    folders.state:SetAttribute("P6_CoverageBalanced", coverageBalanced(folders.agents, config))
    syncRoleCounts(folders, config)
    return agent:GetAttribute("Role")
end

function RoleSystem.Initialize(folders, config)
    local agents = {}
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            ensureAgentProfile(agent, config)
            agent:SetAttribute("Role", "Unassigned")
            agent:SetAttribute("P6RoleInitialized", false)
            table.insert(agents, agent)
        end
    end
    table.sort(agents, function(a, b) return a.Name < b.Name end)

    local tick = folders.state:GetAttribute("WorldTick") or 0
    for _, agent in ipairs(agents) do
        local bestRole, bestScore = chooseRole(agent, folders, config, nil, true)
        assignRole(agent, bestRole, bestScore, tick, "initial_emergent_assignment", folders.state)
    end

    folders.state:SetAttribute("P6_RoleSystemInitialized", true)
    folders.state:SetAttribute("P6_InitialAssignment", true)
    folders.state:SetAttribute("P6_RoleEvaluated", true)
    folders.state:SetAttribute("P6_CoverageBalanced", coverageBalanced(folders.agents, config))
    folders.state:SetAttribute("P6_RoleDecisionRecorded", true)
    syncRoleCounts(folders, config)
end

function RoleSystem.Tick(folders, tick, config)
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            ensureAgentProfile(agent, config)
            recordExperience(agent, folders.state, config)
        end
    end

    if tick % config.RoleEvaluationIntervalTicks ~= 0 then
        syncRoleCounts(folders, config)
        return
    end

    local agents = {}
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then table.insert(agents, agent) end
    end
    table.sort(agents, function(a, b) return a.Name < b.Name end)

    for _, agent in ipairs(agents) do
        local currentRole = agent:GetAttribute("Role")
        local since = agent:GetAttribute("RoleSinceTick") or 0
        local locked, lockReason = isRoleLocked(agent, folders, config)
        local bestRole, bestScore, scores = chooseRole(agent, folders, config, currentRole, false)
        agent:SetAttribute("LastRoleEvaluationTick", tick)
        agent:SetAttribute("SuggestedRole", bestRole)
        agent:SetAttribute("RoleLocked", locked)
        agent:SetAttribute("RoleLockReason", lockReason or "None")
        folders.state:SetAttribute("P6_RoleEvaluated", true)
        folders.state:SetAttribute("P6_RoleDecisionRecorded", true)

        local currentScore = scores[currentRole] or -math.huge
        local age = tick - since
        if not locked
            and bestRole ~= currentRole
            and age >= config.RoleMinDurationTicks
            and bestScore >= currentScore + config.RoleSwitchMargin
        then
            assignRole(agent, bestRole, bestScore, tick, "demand_skill_reassignment", folders.state)
        end
    end

    folders.state:SetAttribute("P6_CoverageBalanced", coverageBalanced(folders.agents, config))
    folders.state:SetAttribute("P6_ReassignmentReady", true)
    syncRoleCounts(folders, config)
end

return RoleSystem

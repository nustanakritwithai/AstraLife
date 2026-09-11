local WorldSimSkills = {}

local SKILLS = {
    "farming", "woodcutting", "mining", "trading", "crafting",
    "sword", "spear", "archery", "riding", "fighting",
    "tactics", "leadership", "logistics", "governance", "diplomacy",
}

local function threshold(level)
    return 20 + level * 15
end

local function ensureSkill(agent, skill)
    local levelKey = "Skill_" .. skill
    local xpKey = "SkillXP_" .. skill
    if agent:GetAttribute(levelKey) == nil then agent:SetAttribute(levelKey, 0) end
    if agent:GetAttribute(xpKey) == nil then agent:SetAttribute(xpKey, 0) end
end

local function gain(agent, skill, amount)
    ensureSkill(agent, skill)
    local levelKey = "Skill_" .. skill
    local xpKey = "SkillXP_" .. skill
    local level = agent:GetAttribute(levelKey) or 0
    local xp = (agent:GetAttribute(xpKey) or 0) + amount
    local leveled = false

    while level < 10 and xp >= threshold(level) do
        xp -= threshold(level)
        level += 1
        leveled = true
    end

    agent:SetAttribute(levelKey, level)
    agent:SetAttribute(xpKey, math.floor(xp * 100 + 0.5) / 100)
    return leveled, level
end

function WorldSimSkills.Ensure(agent)
    for _, skill in ipairs(SKILLS) do ensureSkill(agent, skill) end
end

local function gatherSkill(agent)
    local options = {
        { skill = "farming", amount = (agent:GetAttribute("Carry_Food") or 0) + (agent:GetAttribute("Carry_Water") or 0) },
        { skill = "mining", amount = agent:GetAttribute("Carry_Stone") or 0 },
        { skill = "woodcutting", amount = agent:GetAttribute("Carry_Wood") or 0 },
    }
    local best = options[1]
    for index = 2, #options do
        local candidate = options[index]
        if candidate.amount > best.amount
            or (candidate.amount == best.amount and candidate.skill < best.skill)
        then
            best = candidate
        end
    end
    return best.skill
end

function WorldSimSkills.Tick(agent)
    WorldSimSkills.Ensure(agent)
    local goal = agent:GetAttribute("Goal") or ""
    local role = agent:GetAttribute("Role") or ""
    local skill, xp = nil, 1

    if goal == "GatherResource" then
        skill = gatherSkill(agent)
        xp = 1.5
    elseif goal == "DepositResources" or goal == "DeliverMaterials" then
        skill = "logistics"
        xp = 1.4
    elseif goal == "BuildStructure" then
        skill = "crafting"
        xp = 1.6
    elseif goal == "Communicate" or goal == "Socialize" then
        skill = "diplomacy"
        xp = 1.2
    elseif goal == "Flee" then
        skill = "tactics"
        xp = 1.3
    elseif goal == "Explore" then
        skill = role == "Scout" and "tactics" or "logistics"
        xp = 0.8
    end

    if not skill then return nil end
    local leveled, level = gain(agent, skill, xp)
    if leveled then
        agent:SetAttribute("LastSkillUp", skill)
        agent:SetAttribute("LastSkillLevel", level)
        return { skill = skill, level = level }
    end
    return nil
end

function WorldSimSkills.List()
    return table.clone(SKILLS)
end

return WorldSimSkills

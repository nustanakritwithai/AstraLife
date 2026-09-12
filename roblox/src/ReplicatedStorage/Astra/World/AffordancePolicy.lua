local AffordancePolicy = {}

local DEFAULTS = {
    maxSafeDanger = 0.25,
    maxDrinkDanger = 0.55,
    maxForageDanger = 0.45,
    maxHarvestDanger = 0.50,
    maxWalkSlope = 0.78,
    maxRestSlope = 0.65,
    maxBuildSlope = 0.35,
    minDrinkWater = 0.20,
    minSpringPotential = 0.85,
    minForageFood = 0.05,
    minEatFood = 1.0,
    minHarvestWood = 1.0,
    maxBuildWater = 0.15,
}

local function mergedConfig(options)
    local config = {}
    for key, value in pairs(DEFAULTS) do
        config[key] = options and options[key] ~= nil and options[key] or value
    end
    return config
end

local function effectiveDanger(cell)
    return math.max(
        math.clamp(cell.danger or 0, 0, 1),
        math.clamp(cell.hazardDanger or 0, 0, 1),
        math.clamp(cell.ecosystemDanger or 0, 0, 1)
    )
end

local function baseFacts(cell, options)
    local config = mergedConfig(options)
    local danger = effectiveDanger(cell)
    local hazardBlocked = cell.hazardBlocked == true
    local terrainWalkable = cell.walkable == true
    local slope = math.clamp(cell.slope or 0, 0, 1)
    local water = math.max(0, cell.water or 0)
    local waterPotential = math.clamp(cell.waterPotential or 0, 0, 1)
    local food = math.max(0, cell.food or 0)
    local wood = math.max(0, cell.wood or 0)

    return config, {
        danger = danger,
        baseDanger = math.clamp(cell.danger or 0, 0, 1),
        hazardDanger = math.clamp(cell.hazardDanger or 0, 0, 1),
        ecosystemDanger = math.clamp(cell.ecosystemDanger or 0, 0, 1),
        hazardBlocked = hazardBlocked,
        terrainWalkable = terrainWalkable,
        slope = slope,
        water = water,
        waterPotential = waterPotential,
        food = food,
        wood = wood,
        safe = danger <= config.maxSafeDanger and not hazardBlocked,
    }
end

local function requirePhysicalAccess(facts, config)
    if not facts.terrainWalkable then return false, "terrain_blocked" end
    if facts.hazardBlocked then return false, "hazard_blocked" end
    if facts.slope >= config.maxWalkSlope then return false, "slope_too_steep" end
    return true, "ok"
end

local function requireTerrainAccess(facts, config)
    if not facts.terrainWalkable then return false, "terrain_blocked" end
    if facts.slope >= config.maxWalkSlope then return false, "slope_too_steep" end
    return true, "ok"
end

function AffordancePolicy.Evaluate(cell, action, options)
    if not cell then
        return false, "outside_world", { inWorld = false }
    end

    local config, facts = baseFacts(cell, options)
    facts.inWorld = true
    facts.action = action

    if action == "Walk" then
        local allowed, reason = requirePhysicalAccess(facts, config)
        return allowed, reason, facts
    end

    if action == "Drink" then
        -- Preserve W5's stable action-specific reason contract for dangerous water.
        if facts.hazardBlocked or facts.danger > config.maxDrinkDanger then
            return false, "unsafe_water", facts
        end
        local accessible, accessReason = requireTerrainAccess(facts, config)
        if not accessible then return false, accessReason, facts end
        if facts.water < config.minDrinkWater and facts.waterPotential < config.minSpringPotential then
            return false, "no_drinkable_water", facts
        end
        return true, "ok", facts
    end

    if action == "Eat" then
        if facts.hazardBlocked or facts.danger > config.maxForageDanger then
            return false, "unsafe_food", facts
        end
        local accessible, accessReason = requireTerrainAccess(facts, config)
        if not accessible then return false, accessReason, facts end
        if facts.food < config.minEatFood then return false, "insufficient_food", facts end
        return true, "ok", facts
    end

    if action == "Forage" then
        if facts.hazardBlocked or facts.danger > config.maxForageDanger then
            return false, "unsafe_forage", facts
        end
        local accessible, accessReason = requireTerrainAccess(facts, config)
        if not accessible then return false, accessReason, facts end
        if facts.food <= config.minForageFood then return false, "no_forage", facts end
        return true, "ok", facts
    end

    if action == "HarvestWood" then
        if facts.hazardBlocked or facts.danger > config.maxHarvestDanger then
            return false, "unsafe_harvest", facts
        end
        local accessible, accessReason = requireTerrainAccess(facts, config)
        if not accessible then return false, accessReason, facts end
        if facts.wood < config.minHarvestWood then return false, "insufficient_wood", facts end
        return true, "ok", facts
    end

    if action == "Rest" then
        local walkable, reason = requirePhysicalAccess(facts, config)
        if not walkable then return false, reason, facts end
        if not facts.safe then return false, "unsafe_to_rest", facts end
        if facts.slope >= config.maxRestSlope then return false, "slope_too_steep", facts end
        return true, "ok", facts
    end

    if action == "Build" then
        local walkable, reason = requirePhysicalAccess(facts, config)
        if not walkable then return false, reason, facts end
        if not facts.safe then return false, "unsafe_to_build", facts end
        if facts.slope >= config.maxBuildSlope then return false, "slope_too_steep", facts end
        if facts.water >= config.maxBuildWater then return false, "ground_too_wet", facts end
        return true, "ok", facts
    end

    return false, "unsupported_action", facts
end

function AffordancePolicy.Snapshot(cell, options)
    local actions = { "Walk", "Drink", "Eat", "Forage", "HarvestWood", "Rest", "Build" }
    local snapshot = {}
    for _, action in ipairs(actions) do
        local allowed, reason = AffordancePolicy.Evaluate(cell, action, options)
        snapshot[action] = { allowed = allowed, reason = reason }
    end
    return snapshot
end

function AffordancePolicy.EffectiveDanger(cell)
    if not cell then return 1 end
    return effectiveDanger(cell)
end

return AffordancePolicy

local DurabilityPolicy = {}

local function clamp01(value)
    return math.clamp(value, 0, 1)
end

function DurabilityPolicy.Wear(current, maxValue, workUnits, wearRate)
    maxValue = math.max(1, maxValue or 1)
    current = math.clamp(current == nil and maxValue or current, 0, maxValue)
    local loss = math.max(0, workUnits or 1) * math.max(0, wearRate or 1)
    local after = math.max(0, current - loss)
    return { before = current, after = after, loss = current - after, broken = after <= 0, condition = after / maxValue }
end

function DurabilityPolicy.RepairQuote(current, maxValue, fullRepairMaterials, targetFraction)
    maxValue = math.max(1, maxValue or 1)
    current = math.clamp(current or 0, 0, maxValue)
    targetFraction = clamp01(targetFraction == nil and 1 or targetFraction)
    local target = math.max(current, maxValue * targetFraction)
    local restore = math.max(0, target - current)
    local missingFraction = restore / maxValue
    local materials = {}
    for itemId, fullAmount in pairs(fullRepairMaterials or {}) do
        materials[itemId] = math.max(0, math.ceil(math.max(0, fullAmount) * missingFraction))
    end
    return { current = current, target = target, restore = restore, materials = materials, requiresAuthoritativeSpend = true }
end

function DurabilityPolicy.StructureDecayQuote(maxHealth, tier, exposure, upkeepCovered, elapsedTicks)
    maxHealth = math.max(1, maxHealth or 1)
    tier = math.max(1, tier or 1)
    exposure = clamp01(exposure or 0)
    elapsedTicks = math.max(0, elapsedTicks or 0)
    local baseRate = 0.0005 * maxHealth / tier
    local exposureMultiplier = 1 + exposure * 2
    local upkeepMultiplier = upkeepCovered and 0.15 or 1
    local damage = baseRate * exposureMultiplier * upkeepMultiplier * elapsedTicks
    return { damage = damage, damageFraction = damage / maxHealth, upkeepCovered = upkeepCovered == true }
end

function DurabilityPolicy.UpkeepQuote(parts, intervalTicks)
    intervalTicks = math.max(1, intervalTicks or 100)
    local totalWeight = 0
    local byTier = {}
    for _, part in ipairs(parts or {}) do
        local weight = math.max(0, part.upkeepWeight or 0)
        local tier = math.max(1, part.tier or 1)
        totalWeight += weight
        byTier[tier] = (byTier[tier] or 0) + weight
    end
    local materialUnits = math.ceil(totalWeight * intervalTicks / 100)
    return { totalWeight = totalWeight, materialUnits = materialUnits, byTier = byTier, intervalTicks = intervalTicks }
end

return DurabilityPolicy

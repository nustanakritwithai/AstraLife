local BuildPieceCatalog = require(script.Parent.BuildPieceCatalog)

local MaterialGradeCatalog = {}

local ORDER = { "Scaffold", "Wood", "Stone", "Metal" }

local DEFINITIONS = {
    Scaffold = {
        index = 1,
        healthMultiplier = 0.35,
        damageMultiplier = {
            Generic = 1.15,
            Melee = 1.15,
            Fire = 1.45,
            Explosion = 1.30,
        },
        resourceType = "Wood",
        recipeMultiplier = 0.25,
        repairCostFraction = 0.30,
        demolishRefundFraction = 0.35,
        material = Enum.Material.WoodPlanks,
        color = Color3.fromRGB(156, 122, 82),
        transparency = 0.18,
    },
    Wood = {
        index = 2,
        healthMultiplier = 1.00,
        damageMultiplier = {
            Generic = 1.00,
            Melee = 1.00,
            Fire = 1.30,
            Explosion = 1.12,
        },
        resourceType = "Wood",
        recipeMultiplier = 1.00,
        repairCostFraction = 0.35,
        demolishRefundFraction = 0.30,
        material = Enum.Material.WoodPlanks,
        color = Color3.fromRGB(127, 88, 55),
        transparency = 0,
    },
    Stone = {
        index = 3,
        healthMultiplier = 2.20,
        damageMultiplier = {
            Generic = 0.62,
            Melee = 0.55,
            Fire = 0.45,
            Explosion = 0.82,
        },
        resourceType = "Stone",
        recipeMultiplier = 1.25,
        repairCostFraction = 0.28,
        demolishRefundFraction = 0.25,
        material = Enum.Material.Slate,
        color = Color3.fromRGB(112, 116, 118),
        transparency = 0,
    },
    Metal = {
        index = 4,
        healthMultiplier = 4.00,
        damageMultiplier = {
            Generic = 0.42,
            Melee = 0.32,
            Fire = 0.30,
            Explosion = 0.62,
        },
        resourceType = "Metal",
        recipeMultiplier = 1.10,
        repairCostFraction = 0.24,
        demolishRefundFraction = 0.20,
        material = Enum.Material.Metal,
        color = Color3.fromRGB(82, 91, 98),
        transparency = 0,
    },
}

local BASE_HEALTH = {
    Foundation = 500,
    Wall = 350,
    Floor = 300,
    Roof = 260,
    Stairs = 320,
}

local function cloneRecipe(recipe)
    local result = {}
    for resourceType, amount in pairs(recipe or {}) do
        result[resourceType] = amount
    end
    return result
end

local function baseUnits(pieceType)
    local definition = BuildPieceCatalog.Get(pieceType)
    if not definition then return nil end
    local total = 0
    for _, amount in pairs(definition.cost or {}) do
        total += math.max(0, tonumber(amount) or 0)
    end
    return math.max(1, total), definition
end

function MaterialGradeCatalog.Get(name)
    return DEFINITIONS[name]
end

function MaterialGradeCatalog.IsValid(name)
    return DEFINITIONS[name] ~= nil
end

function MaterialGradeCatalog.DefaultGrade()
    return "Wood"
end

function MaterialGradeCatalog.Order()
    local copy = {}
    for index, value in ipairs(ORDER) do copy[index] = value end
    return copy
end

function MaterialGradeCatalog.Next(name)
    local definition = DEFINITIONS[name]
    if not definition then return nil end
    return ORDER[definition.index + 1]
end

function MaterialGradeCatalog.BaseHealth(pieceType)
    local definition = BuildPieceCatalog.Get(pieceType)
    if not definition then return nil end
    return BASE_HEALTH[definition.category] or 300
end

function MaterialGradeCatalog.MaxHealth(pieceType, grade)
    local base = MaterialGradeCatalog.BaseHealth(pieceType)
    local definition = DEFINITIONS[grade]
    if not base or not definition then return nil end
    return base * definition.healthMultiplier
end

function MaterialGradeCatalog.FullRecipe(pieceType, grade)
    local units = baseUnits(pieceType)
    local definition = DEFINITIONS[grade]
    if not units or not definition then return nil end
    return {
        [definition.resourceType] = math.max(0.01, math.ceil(units * definition.recipeMultiplier * 100) / 100),
    }
end

function MaterialGradeCatalog.UpgradeRecipe(pieceType, currentGrade, targetGrade)
    local nextGrade = MaterialGradeCatalog.Next(currentGrade)
    if not nextGrade then return nil, "max_grade" end
    if targetGrade and targetGrade ~= nextGrade then return nil, "upgrade_must_be_next_grade" end
    return MaterialGradeCatalog.FullRecipe(pieceType, nextGrade), nil, nextGrade
end

function MaterialGradeCatalog.RepairRecipe(pieceType, grade, missingHealthRatio)
    local full = MaterialGradeCatalog.FullRecipe(pieceType, grade)
    local definition = DEFINITIONS[grade]
    if not full or not definition then return nil end
    local ratio = math.clamp(tonumber(missingHealthRatio) or 0, 0, 1)
    local result = {}
    for resourceType, amount in pairs(full) do
        result[resourceType] = math.max(0.01, amount * definition.repairCostFraction * ratio)
    end
    return result
end

function MaterialGradeCatalog.DemolishRefund(pieceType, grade)
    local full = MaterialGradeCatalog.FullRecipe(pieceType, grade)
    local definition = DEFINITIONS[grade]
    if not full or not definition then return {} end
    local result = {}
    for resourceType, amount in pairs(full) do
        result[resourceType] = amount * definition.demolishRefundFraction
    end
    return cloneRecipe(result)
end

function MaterialGradeCatalog.DamageMultiplier(grade, damageType)
    local definition = DEFINITIONS[grade] or DEFINITIONS.Wood
    return definition.damageMultiplier[damageType or "Generic"]
        or definition.damageMultiplier.Generic
        or 1
end

function MaterialGradeCatalog.Visual(grade)
    local definition = DEFINITIONS[grade] or DEFINITIONS.Wood
    return {
        material = definition.material,
        color = definition.color,
        transparency = definition.transparency or 0,
    }
end

return MaterialGradeCatalog

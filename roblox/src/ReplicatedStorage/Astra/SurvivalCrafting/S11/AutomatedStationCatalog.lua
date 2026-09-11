local AutomatedStationCatalog = {}

local profiles = {
    Quarry = {
        cycleTicks = 12,
        fuelPerCycle = 1,
        fuelTag = "fuel",
        outputCapacityRequired = 7,
        sourceRequirement = "mineral_deposit",
        requestedOutputs = { StoneChunk = 4, IronOre = 2, SulfurOre = 1 },
    },
    Sawmill = {
        cycleTicks = 10,
        fuelPerCycle = 1,
        fuelTag = "fuel",
        outputCapacityRequired = 6,
        sourceRequirement = "forest_wood",
        requestedOutputs = { Log = 6 },
    },
    SalvageRecycler = {
        cycleTicks = 8,
        fuelPerCycle = 0,
        fuelTag = nil,
        outputCapacityRequired = 4,
        sourceRequirement = "salvage_input",
        requestedOutputs = { Scrap = 3, MetalFragment = 1 },
    },
}

function AutomatedStationCatalog.Get(id) return profiles[id] end
function AutomatedStationCatalog.All() return profiles end

function AutomatedStationCatalog.QuoteCycle(id, context)
    local profile = profiles[id]
    if not profile then return nil, "unknown_station" end
    context = context or {}
    local efficiency = math.clamp(context.efficiency or 1, 0.25, 2.5)
    local availableCapacity = math.max(0, context.outputFreeCapacity or 0)
    if availableCapacity < profile.outputCapacityRequired then return nil, "output_capacity_low" end
    if profile.fuelPerCycle > 0 and (context.availableFuel or 0) < profile.fuelPerCycle then return nil, "fuel_low" end
    local outputs = {}
    for itemId, amount in pairs(profile.requestedOutputs) do
        outputs[itemId] = math.max(1, math.floor(amount * efficiency + 0.5))
    end
    return {
        stationId = id,
        cycleTicks = math.max(1, math.floor(profile.cycleTicks / efficiency + 0.5)),
        fuelRequired = profile.fuelPerCycle,
        fuelTag = profile.fuelTag,
        sourceRequirement = profile.sourceRequirement,
        requestedOutputs = outputs,
        requiresAuthoritativeResourceCommit = true,
    }
end

return AutomatedStationCatalog

local SeededRandom = require(script.Parent.SeededRandom)
local DirtyTracker = require(script.Parent.DirtyTracker)
local WorldEventBus = require(script.Parent.WorldEventBus)
local WorldGrid = require(script.Parent.WorldGrid)
local EnvironmentQuery = require(script.Parent.EnvironmentQuery)
local WorldSnapshot = require(script.Parent.WorldSnapshot)
local WorldClock = require(script.Parent.WorldClock)

local W0Verifier = {}

local function check(condition, name, results)
    results[name] = condition == true
    return condition == true
end

function W0Verifier.Run()
    local results = {}

    local rngA = SeededRandom.new(20904)
    local rngB = SeededRandom.new(20904)
    local deterministic = true
    for _ = 1, 8 do
        if rngA:NextInteger(1, 100000) ~= rngB:NextInteger(1, 100000) then
            deterministic = false
            break
        end
    end
    check(deterministic, "deterministicRng", results)

    local dirty = DirtyTracker.new()
    local grid = WorldGrid.new({ width = 4, depth = 4, cellSize = 10, origin = Vector3.zero })
    local cell, changed = grid:UpdateCell(2, 2, {
        water = 0.5,
        food = 2,
        danger = 0.1,
        vegetation = 1,
    }, dirty)
    check(changed and cell and cell.version == 1 and dirty:Count() == 1, "gridDirtyTracking", results)

    local query = EnvironmentQuery.new(grid)
    local affordances = query:GetAffordancesAt(grid:CellCenter(2, 2))
    check(
        affordances.canDrink
            and affordances.canEat
            and affordances.canRest
            and affordances.safe
            and not affordances.canBuild,
        "environmentQuery",
        results
    )

    local dirtyEntries = dirty:Drain(16)
    local snapshotA = WorldSnapshot.BuildDelta({ seed = 20904, tick = 4, simTime = 1 }, grid, dirtyEntries)
    local snapshotB = WorldSnapshot.BuildDelta({ seed = 20904, tick = 4, simTime = 1 }, grid, dirtyEntries)
    check(snapshotA.fingerprint == snapshotB.fingerprint and snapshotA.cells["2:2"] ~= nil, "snapshotFingerprint", results)

    local bus = WorldEventBus.new(8)
    local received = {}
    bus:Subscribe("test", function(event)
        table.insert(received, event.sequence)
    end)
    bus:Emit("test", { value = 1 }, 1)
    bus:Emit("test", { value = 2 }, 2)
    bus:Flush()
    check(#received == 2 and received[1] == 1 and received[2] == 2, "eventOrdering", results)

    local clock = WorldClock.new({ fixedStep = 0.25 })
    local fast = 0
    local slow = 0
    clock:RegisterSystem("fast", 1, function() fast += 1 end, 10)
    clock:RegisterSystem("slow", 2, function() slow += 1 end, 20)
    for _ = 1, 4 do
        clock:StepOnce()
    end
    check(clock.tick == 4 and fast == 4 and slow == 2, "multiRateClock", results)

    local passed = true
    for _, value in pairs(results) do
        if not value then
            passed = false
            break
        end
    end

    return passed, results
end

return W0Verifier

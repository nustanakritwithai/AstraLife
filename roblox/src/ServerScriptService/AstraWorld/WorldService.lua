local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("World")
local SeededRandom = require(WorldModules.SeededRandom)
local DirtyTracker = require(WorldModules.DirtyTracker)
local WorldEventBus = require(WorldModules.WorldEventBus)
local WorldGrid = require(WorldModules.WorldGrid)
local EnvironmentQuery = require(WorldModules.EnvironmentQuery)
local WorldSnapshot = require(WorldModules.WorldSnapshot)
local WorldClock = require(WorldModules.WorldClock)
local W0Verifier = require(WorldModules.W0Verifier)

local WorldService = {}

local runtime = nil
local heartbeatConnection = nil

local function createStateFolder()
    local existing = Workspace:FindFirstChild("AstraLivingWorldState")
    if existing then
        return existing
    end
    local folder = Instance.new("Folder")
    folder.Name = "AstraLivingWorldState"
    folder.Parent = Workspace
    return folder
end

local function configureState(state, config, origin)
    state:SetAttribute("Version", "W0")
    state:SetAttribute("W0Status", "BOOTING")
    state:SetAttribute("Seed", config.seed)
    state:SetAttribute("LivingWorldTick", 0)
    state:SetAttribute("SimSeconds", 0)
    state:SetAttribute("FixedStep", config.fixedStep)
    state:SetAttribute("GridWidth", config.width)
    state:SetAttribute("GridDepth", config.depth)
    state:SetAttribute("CellSize", config.cellSize)
    state:SetAttribute("OriginX", origin.X)
    state:SetAttribute("OriginY", origin.Y)
    state:SetAttribute("OriginZ", origin.Z)
    state:SetAttribute("MaterializedCells", 0)
    state:SetAttribute("DirtyCells", 0)
    state:SetAttribute("SnapshotFingerprint", "00000000")
    state:SetAttribute("EventSequence", 0)
    state:SetAttribute("DroppedEvents", 0)
end

function WorldService.Start(options)
    if runtime then
        return runtime
    end

    options = options or {}
    local config = {
        seed = options.seed or 20904,
        fixedStep = options.fixedStep or 0.25,
        width = options.width or 64,
        depth = options.depth or 64,
        cellSize = options.cellSize or 16,
        maxCatchUpSteps = options.maxCatchUpSteps or 8,
    }
    local origin = options.origin or Vector3.new(
        -(config.width * config.cellSize) / 2,
        0,
        -(config.depth * config.cellSize) / 2
    )

    local state = createStateFolder()
    configureState(state, config, origin)

    local rng = SeededRandom.new(config.seed)
    local dirty = DirtyTracker.new()
    local events = WorldEventBus.new(512)
    local grid = WorldGrid.new({
        width = config.width,
        depth = config.depth,
        cellSize = config.cellSize,
        origin = origin,
    })
    local query = EnvironmentQuery.new(grid)
    local clock = WorldClock.new({
        fixedStep = config.fixedStep,
        maxCatchUpSteps = config.maxCatchUpSteps,
    })

    runtime = {
        config = config,
        state = state,
        clock = clock,
        rng = rng,
        dirty = dirty,
        events = events,
        grid = grid,
        query = query,
        lastSnapshot = nil,
    }

    clock:RegisterSystem("W0.StateReplication", 4, function(context)
        local entries = dirty:Drain(256)
        local snapshot = WorldSnapshot.BuildDelta({
            seed = config.seed,
            tick = context.tick,
            simTime = context.simTime,
        }, grid, entries)
        runtime.lastSnapshot = snapshot

        state:SetAttribute("LivingWorldTick", context.tick)
        state:SetAttribute("SimSeconds", context.simTime)
        state:SetAttribute("MaterializedCells", grid:GetMaterializedCount())
        state:SetAttribute("DirtyCells", dirty:Count())
        state:SetAttribute("SnapshotFingerprint", snapshot.fingerprint)

        local stats = events:GetStats()
        state:SetAttribute("EventSequence", stats.sequence)
        state:SetAttribute("DroppedEvents", stats.dropped)

        if #entries > 0 then
            events:Emit("world.snapshot", snapshot, context.tick)
        end
    end, 900)

    clock:RegisterSystem("W0.EventFlush", 1, function()
        events:Flush(128)
    end, 1000)

    local passed, checks = W0Verifier.Run()
    state:SetAttribute("W0Status", passed and "PASS" or "FAIL")
    for name, value in pairs(checks) do
        state:SetAttribute("W0Check_" .. name, value)
    end

    events:Emit("world.started", {
        seed = config.seed,
        width = config.width,
        depth = config.depth,
        cellSize = config.cellSize,
    }, 0)

    heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        clock:Update(deltaTime)
    end)

    return runtime
end

function WorldService.GetRuntime()
    return runtime
end

function WorldService.IsStarted()
    return runtime ~= nil
end

function WorldService.Stop()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    runtime = nil
end

return WorldService

local WorldClock = {}
WorldClock.__index = WorldClock

function WorldClock.new(config)
    config = config or {}
    local fixedStep = config.fixedStep or 0.25
    assert(fixedStep > 0, "fixedStep must be > 0")

    return setmetatable({
        fixedStep = fixedStep,
        maxCatchUpSteps = config.maxCatchUpSteps or 8,
        tick = config.startTick or 0,
        simTime = (config.startTick or 0) * fixedStep,
        _accumulator = 0,
        _systems = {},
        _sorted = false,
    }, WorldClock)
end

function WorldClock:RegisterSystem(name, everyTicks, callback, priority)
    assert(type(name) == "string" and name ~= "", "system name is required")
    assert(type(callback) == "function", "callback must be a function")
    everyTicks = math.max(1, math.floor(everyTicks or 1))

    for _, system in ipairs(self._systems) do
        assert(system.name ~= name, "system already registered: " .. name)
    end

    table.insert(self._systems, {
        name = name,
        everyTicks = everyTicks,
        callback = callback,
        priority = priority or 100,
    })
    self._sorted = false
end

function WorldClock:_sortSystems()
    if self._sorted then
        return
    end
    table.sort(self._systems, function(a, b)
        if a.priority == b.priority then
            return a.name < b.name
        end
        return a.priority < b.priority
    end)
    self._sorted = true
end

function WorldClock:StepOnce()
    self:_sortSystems()
    self.tick += 1
    self.simTime = self.tick * self.fixedStep

    local context = {
        tick = self.tick,
        simTime = self.simTime,
        fixedStep = self.fixedStep,
    }

    for _, system in ipairs(self._systems) do
        if self.tick % system.everyTicks == 0 then
            local ok, err = pcall(system.callback, context)
            if not ok then
                warn(string.format("[AstraLife][WorldClock] %s failed: %s", system.name, tostring(err)))
            end
        end
    end

    return context
end

function WorldClock:Update(realDeltaTime)
    realDeltaTime = math.max(0, realDeltaTime or 0)
    local maxAccumulated = self.fixedStep * self.maxCatchUpSteps
    self._accumulator = math.min(self._accumulator + realDeltaTime, maxAccumulated)

    local steps = 0
    while self._accumulator >= self.fixedStep and steps < self.maxCatchUpSteps do
        self._accumulator -= self.fixedStep
        self:StepOnce()
        steps += 1
    end
    return steps
end

function WorldClock:GetState()
    return {
        tick = self.tick,
        simTime = self.simTime,
        fixedStep = self.fixedStep,
        accumulator = self._accumulator,
    }
end

return WorldClock

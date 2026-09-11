local CraftQueue = {}
CraftQueue.__index = CraftQueue

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

function CraftQueue.new(maxJobs)
    return setmetatable({
        maxJobs = math.max(1, maxJobs or 32),
        jobs = {},
        byId = {},
        seenTransactions = {},
        nextId = 1,
    }, CraftQueue)
end

function CraftQueue:Enqueue(spec, transactionId, tick)
    if transactionId and self.seenTransactions[transactionId] then
        return self.byId[self.seenTransactions[transactionId]], "duplicate"
    end
    if #self.jobs >= self.maxJobs then return nil, "queue_full" end
    assert(type(spec) == "table" and type(spec.recipeId) == "string", "recipe spec required")
    local quantity = math.max(1, math.floor(spec.quantity or 1))
    local craftTicks = math.max(1, math.floor(spec.craftTicks or 1))
    local id = "craft:" .. tostring(self.nextId)
    self.nextId += 1
    local job = {
        id = id,
        recipeId = spec.recipeId,
        quantity = quantity,
        station = spec.station or "hand",
        craftTicks = craftTicks,
        totalTicks = craftTicks * quantity,
        remainingTicks = craftTicks * quantity,
        inputs = copy(spec.inputs or {}),
        outputs = copy(spec.outputs or {}),
        state = "queued",
        createdTick = tick or 0,
        startedTick = nil,
        completedTick = nil,
        transactionId = transactionId,
    }
    table.insert(self.jobs, job)
    self.byId[id] = job
    if transactionId then self.seenTransactions[transactionId] = id end
    return job, "queued"
end

function CraftQueue:Cancel(jobId)
    local job = self.byId[jobId]
    if not job then return nil, "job_not_found" end
    if job.state == "committed" or job.state == "completed_pending_commit" then return nil, "already_completed" end
    job.state = "cancelled"
    return job
end

function CraftQueue:Step(tick, workUnits)
    workUnits = math.max(1, workUnits or 1)
    local active
    for _, job in ipairs(self.jobs) do
        if job.state == "queued" or job.state == "running" then active = job break end
    end
    if not active then return nil, "idle" end
    if active.state == "queued" then
        active.state = "running"
        active.startedTick = tick or 0
    end
    active.remainingTicks = math.max(0, active.remainingTicks - workUnits)
    if active.remainingTicks == 0 then
        active.state = "completed_pending_commit"
        active.completedTick = tick or 0
        return active, "ready_to_commit"
    end
    return active, "progress"
end

function CraftQueue:Commit(jobId, accepted)
    local job = self.byId[jobId]
    if not job then return nil, "job_not_found" end
    if job.state ~= "completed_pending_commit" then return nil, "not_ready" end
    job.state = accepted == false and "commit_failed" or "committed"
    return job
end

function CraftQueue:Snapshot()
    local out = {}
    for index, job in ipairs(self.jobs) do out[index] = copy(job) end
    return out
end

return CraftQueue

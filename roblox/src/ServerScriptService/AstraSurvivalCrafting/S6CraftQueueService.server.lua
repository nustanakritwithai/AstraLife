local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local SourceReader = require(SurvivalCrafting.Core.SourceReader)
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local CraftQueue = require(SurvivalCrafting.S6.CraftQueue)
local S6Verifier = require(SurvivalCrafting.S6.S6Verifier)

local scope = StateWriter.Scope("S6CraftQueue")
local queue = CraftQueue.new(32)
local api = Instance.new("BindableFunction")
api.Name = "S6CraftQueueApi"
api.Parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService
local lastTick = -1

local function publish()
    local snapshot = queue:Snapshot()
    local active
    for _, job in ipairs(snapshot) do
        if job.state == "queued" or job.state == "running" or job.state == "completed_pending_commit" then active = job break end
    end
    StateWriter.SetMany(scope, {
        Version = "S6-1",
        QueueLength = #snapshot,
        ActiveJobId = active and active.id or "None",
        ActiveState = active and active.state or "idle",
        OwnsInventoryMutation = false,
        OwnsRecipeCatalog = false,
        RequiresExternalCommitAdapter = true,
    })
end

api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "Enqueue" then
        local job, reason = queue:Enqueue(payload.spec or {}, payload.transactionId, SourceReader.ReadCadence().agentTick)
        publish()
        return job, reason
    elseif action == "Cancel" then
        local job, reason = queue:Cancel(payload.jobId)
        publish()
        return job, reason
    elseif action == "Commit" then
        local job, reason = queue:Commit(payload.jobId, payload.accepted)
        publish()
        return job, reason
    elseif action == "Snapshot" then
        return queue:Snapshot()
    end
    return nil, "unknown_action"
end

RunService.Heartbeat:Connect(function()
    local tick = SourceReader.ReadCadence().agentTick
    if tick ~= lastTick then
        lastTick = tick
        queue:Step(tick, 1)
        publish()
    end
end)

scope:SetAttribute("Version", "S6-1")
S6Verifier.Verify(CraftQueue, scope)
publish()

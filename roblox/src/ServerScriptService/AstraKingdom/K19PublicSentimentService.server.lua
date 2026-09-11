local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Kingdom = ReplicatedStorage.Astra.Kingdom
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local PublicSentiment = require(Kingdom.K19.PublicSentiment)
local K19Verifier = require(Kingdom.K19.K19Verifier)

local scope = StateWriter.Scope("K19PublicSentiment")
local events = {}
local seen = {}
local MAX_EVENTS = 64
local lastTick = -1

local function prune(tick)
    local kept = {}
    for _, event in ipairs(events) do
        if tick - event.tick <= 120 then table.insert(kept, event) end
    end
    events = kept
end

local function publish(tick)
    prune(tick)
    local before = K19Verifier.Capture(SourceReader)
    local values = PublicSentiment.Evaluate(SourceReader.Snapshot(), events, tick, StateWriter.Root())
    values.SourceWorldTick = tick
    values.Version = "K19-1"
    values.OwnsAgentMemory = false
    values.OwnsBelief = false
    values.OwnsPolitics = false
    StateWriter.SetMany(scope, values)
    K19Verifier.Verify(scope, before, K19Verifier.Capture(SourceReader))
end

local api = Instance.new("BindableFunction")
api.Name = "K19PublicSentimentApi"
api.Parent = ServerScriptService:FindFirstChild("AstraKingdom") or ServerScriptService
api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "RecordEvent" then
        local eventId = tostring(payload.eventId or "")
        if eventId == "" then return nil, "event_id_required" end
        if seen[eventId] then return seen[eventId] end
        local tick = SourceReader.ReadCadence().agentTick
        local event = {
            eventId = eventId,
            kind = tostring(payload.kind or "generic"),
            magnitude = math.max(-1, math.min(1, tonumber(payload.magnitude) or 0)),
            tick = tick,
        }
        seen[eventId] = event
        table.insert(events, event)
        while #events > MAX_EVENTS do
            local old = table.remove(events, 1)
            seen[old.eventId] = nil
        end
        publish(tick)
        return event
    elseif action == "Snapshot" then
        return { events = events, state = PublicSentiment.Evaluate(SourceReader.Snapshot(), events, SourceReader.ReadCadence().agentTick, StateWriter.Root()) }
    end
    return nil, "unknown_action"
end

RunService.Heartbeat:Connect(function()
    local tick = SourceReader.ReadCadence().agentTick
    if tick ~= lastTick then
        lastTick = tick
        publish(tick)
    end
end)
publish(SourceReader.ReadCadence().agentTick)

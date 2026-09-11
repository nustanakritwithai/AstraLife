local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Kingdom = ReplicatedStorage.Astra.Kingdom
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local Chronicle = require(Kingdom.K20.Chronicle)
local K20Verifier = require(Kingdom.K20.K20Verifier)

local scope = StateWriter.Scope("K20Chronicle")
local root = StateWriter.Root()
local events, seen, observed = {}, {}, {}
local MAX_EVENTS = 256
local lastTick = -1

local function publish()
    local values = Chronicle.Aggregate(events)
    values.Version = "K20-1"
    values.OwnsGameplay = false
    StateWriter.SetMany(scope, values)
end

local function append(input)
    local tick = SourceReader.ReadCadence().agentTick
    local event = Chronicle.Normalize(input, tick)
    if event.eventId == "" then return nil, "event_id_required" end
    if seen[event.eventId] then return seen[event.eventId] end
    local before = K20Verifier.Capture(SourceReader)
    seen[event.eventId] = event
    table.insert(events, event)
    while #events > MAX_EVENTS do
        local old = table.remove(events, 1)
        seen[old.eventId] = nil
    end
    publish()
    K20Verifier.Verify(scope, before, K20Verifier.Capture(SourceReader))
    return event
end

local function severityForState(serialized)
    if string.find(serialized, "CRISIS", 1, true)
        or string.find(serialized, "ERROR", 1, true)
        or string.find(serialized, "SEVERE", 1, true)
    then
        return "crisis"
    end
    return "notice"
end

local function observeKingdomState(tick)
    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("Folder") and child ~= scope then
            local attrs = child:GetAttributes()
            for key, value in pairs(attrs) do
                if string.match(key, "State$") or string.match(key, "Status$") then
                    local id = child.Name .. ":" .. key
                    local serialized = tostring(value)
                    if observed[id] ~= nil and observed[id] ~= serialized then
                        append({
                            eventId = string.format("auto:%s:%s:%d", child.Name, key, tick),
                            category = "state_change",
                            subject = child.Name,
                            severity = severityForState(serialized),
                            title = child.Name .. " " .. key .. " changed",
                            summary = tostring(observed[id]) .. " -> " .. serialized,
                            source = "K20Observer",
                        })
                    end
                    observed[id] = serialized
                end
            end
        end
    end
end

local api = Instance.new("BindableFunction")
api.Name = "K20ChronicleApi"
api.Parent = ServerScriptService:FindFirstChild("AstraKingdom") or ServerScriptService
api.OnInvoke = function(action, payload)
    if action == "Append" then return append(payload or {}) end
    if action == "Snapshot" then return { events = events, aggregate = Chronicle.Aggregate(events) } end
    return nil, "unknown_action"
end

RunService.Heartbeat:Connect(function()
    local tick = SourceReader.ReadCadence().agentTick
    if tick ~= lastTick then
        lastTick = tick
        observeKingdomState(tick)
        publish()
    end
end)
publish()
K20Verifier.Verify(scope, K20Verifier.Capture(SourceReader), K20Verifier.Capture(SourceReader))

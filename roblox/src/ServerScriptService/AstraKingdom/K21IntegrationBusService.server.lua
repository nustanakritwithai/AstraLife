local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Kingdom = ReplicatedStorage.Astra.Kingdom
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local IntegrationEnvelope = require(Kingdom.K21.IntegrationEnvelope)
local K21Verifier = require(Kingdom.K21.K21Verifier)

local scope = StateWriter.Scope("K21IntegrationBus")
local root = StateWriter.Root()
local parent = ServerScriptService:FindFirstChild("AstraKingdom") or ServerScriptService
local queue, seen = {}, {}
local MAX_EVENTS = 256
local forwardErrors = 0
local lastTick = -1

local busEvent = Instance.new("BindableEvent")
busEvent.Name = "K21IntegrationEvent"
busEvent.Parent = parent

local api = Instance.new("BindableFunction")
api.Name = "K21IntegrationBusApi"
api.Parent = parent

local function health()
    local installed, pass, err, other = 0, 0, 0, 0
    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("Folder") and child ~= scope then
            local found = false
            for key, value in pairs(child:GetAttributes()) do
                if string.match(key, "^K%d+Status$") then
                    found = true
                    if value == "PASS" then pass += 1
                    elseif value == "ERROR" then err += 1
                    else other += 1 end
                end
            end
            if found then installed += 1 end
        end
    end
    return installed, pass, err, other
end

local function publishState()
    local installed, pass, err, other = health()
    StateWriter.SetMany(scope, {
        Version = "K21-1",
        ContractVersion = "K21-1",
        QueuedEventCount = #queue,
        SeenEventCount = #queue,
        InstalledModuleCount = installed,
        PassingModuleCount = pass,
        ErrorModuleCount = err,
        OtherModuleCount = other,
        ForwardErrors = forwardErrors,
        OwnsGameplay = false,
        OwnsWorld = false,
        OwnsAgentDecisions = false,
    })
end

local function forwardChronicle(envelope)
    local chronicle = parent:FindFirstChild("K20ChronicleApi")
    if chronicle and chronicle:IsA("BindableFunction") then
        local ok = pcall(function()
            chronicle:Invoke("Append", {
                eventId = "bus:" .. envelope.eventId,
                tick = envelope.tick,
                category = envelope.domain,
                subject = envelope.subject,
                severity = envelope.severity,
                title = envelope.kind,
                summary = envelope.summary,
                source = envelope.source,
            })
        end)
        if not ok then forwardErrors += 1 end
    end
end

local function publish(input)
    local tick = SourceReader.ReadCadence().agentTick
    local envelope = IntegrationEnvelope.Build(input or {}, tick)
    local valid, reason = IntegrationEnvelope.Validate(envelope)
    if not valid then return nil, reason end
    if seen[envelope.eventId] then return seen[envelope.eventId] end

    local before = K21Verifier.Capture(SourceReader)
    seen[envelope.eventId] = envelope
    table.insert(queue, envelope)
    while #queue > MAX_EVENTS do
        local old = table.remove(queue, 1)
        seen[old.eventId] = nil
    end
    busEvent:Fire(envelope)
    forwardChronicle(envelope)
    publishState()
    K21Verifier.Verify(scope, before, K21Verifier.Capture(SourceReader))
    return envelope
end

api.OnInvoke = function(action, payload)
    if action == "Publish" then return publish(payload or {}) end
    if action == "Snapshot" then
        local installed, pass, err, other = health()
        return { events = queue, installed = installed, pass = pass, error = err, other = other }
    end
    return nil, "unknown_action"
end

RunService.Heartbeat:Connect(function()
    local tick = SourceReader.ReadCadence().agentTick
    if tick ~= lastTick then
        lastTick = tick
        publishState()
    end
end)
publishState()
K21Verifier.Verify(scope, K21Verifier.Capture(SourceReader), K21Verifier.Capture(SourceReader))

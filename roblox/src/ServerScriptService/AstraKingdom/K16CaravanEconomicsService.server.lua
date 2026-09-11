local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kingdom = ReplicatedStorage.Astra.Kingdom
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local CaravanEconomics = require(Kingdom.K16.CaravanEconomics)
local K16Verifier = require(Kingdom.K16.K16Verifier)

local scope = StateWriter.Scope("K16CaravanEconomics")
local plans = {}
local outcomes = {}
local MAX_PLANS = 64

local function publish()
    local aggregate = CaravanEconomics.Aggregate(plans)
    aggregate.OutcomeCount = #outcomes
    aggregate.Version = "K16-1"
    aggregate.OwnsMovement = false
    aggregate.OwnsNavigation = false
    aggregate.OwnsInventoryTransfer = false
    StateWriter.SetMany(scope, aggregate)
end

local function mutate(fn)
    local before = K16Verifier.Capture(SourceReader)
    local result = fn()
    publish()
    local after = K16Verifier.Capture(SourceReader)
    K16Verifier.Verify(scope, before, after)
    return result
end

local api = Instance.new("BindableFunction")
api.Name = "K16CaravanEconomicsApi"
api.Parent = ServerScriptService:FindFirstChild("AstraKingdom") or ServerScriptService

api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "CreatePlan" then
        return mutate(function()
            local plan = CaravanEconomics.BuildPlan(payload)
            plan.PlanId = tostring(payload.planId or ("caravan-" .. tostring(#plans + 1)))
            plan.Status = "PLANNED"
            table.insert(plans, plan)
            while #plans > MAX_PLANS do table.remove(plans, 1) end
            return plan
        end)
    elseif action == "RecordOutcome" then
        return mutate(function()
            local row = {
                planId = tostring(payload.planId or "unknown"),
                delivered = math.max(0, tonumber(payload.delivered) or 0),
                realizedProfit = tonumber(payload.realizedProfit) or 0,
                outcome = tostring(payload.outcome or "UNKNOWN"),
            }
            table.insert(outcomes, row)
            while #outcomes > MAX_PLANS do table.remove(outcomes, 1) end
            return row
        end)
    elseif action == "Snapshot" then
        return { plans = plans, outcomes = outcomes, aggregate = CaravanEconomics.Aggregate(plans) }
    end
    return nil, "unknown_action"
end

publish()
K16Verifier.Verify(scope, K16Verifier.Capture(SourceReader), K16Verifier.Capture(SourceReader))

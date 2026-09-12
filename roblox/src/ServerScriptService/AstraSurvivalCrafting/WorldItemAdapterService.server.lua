local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SurvivalCrafting = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("SurvivalCrafting")
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local WorldItemAdapter = require(SurvivalCrafting.Adapter.WorldItemAdapter)
local I2Verifier = require(SurvivalCrafting.Adapter.I2Verifier)

-- I2 composition: exposes the WorldGatherReceipt -> S item yield conversion as
-- a callable contract. The adapter never withdraws Living World resources
-- itself; W6 stays the authoritative withdrawer and callers pass committed
-- transaction results in as receipts.
local scope = StateWriter.Scope("I2WorldItemAdapter")

local api = Instance.new("BindableFunction")
api.Name = "I2WorldItemAdapterApi"
api.Parent = ServerScriptService:FindFirstChild("AstraSurvivalCrafting") or ServerScriptService
api.OnInvoke = function(action, payload)
    payload = payload or {}
    if action == "BuildReceipt" then return WorldItemAdapter.BuildReceipt(payload) end
    if action == "ValidateReceipt" then return WorldItemAdapter.ValidateReceipt(payload) end
    if action == "Convert" then return WorldItemAdapter.Convert(payload, payload.options) end
    if action == "ResolveSourceKind" then
        return WorldItemAdapter.ResolveSourceKind(payload.worldResourceType, payload.context)
    end
    return nil, "unknown_action"
end

I2Verifier.Verify(WorldItemAdapter, scope)

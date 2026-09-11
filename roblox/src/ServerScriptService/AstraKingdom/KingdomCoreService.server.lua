local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Core = Kingdom:WaitForChild("Core")

local Contract = require(Core.Contract)
local SourceReader = require(Core.SourceReader)
local StateWriter = require(Core.StateWriter)
local K0Verifier = require(Core.K0Verifier)

local root = StateWriter.Root()
root:SetAttribute("Module", "KingdomK0Core")
root:SetAttribute("Status", "ONLINE")
root:SetAttribute("SourcePolicy", "read-only")
Contract.ApplyOwnershipAttributes(root)

local lastAgentTick = -1
local lastLivingTick = -1

local function publish()
    local snapshot = SourceReader.Snapshot()
    local cadence = snapshot.cadence

    root:SetAttribute("ObservedAgentTick", cadence.agentTick)
    root:SetAttribute("ObservedLivingWorldTick", cadence.livingWorldTick)
    root:SetAttribute("ObservedPopulation", snapshot.population.total)
    root:SetAttribute("ObservedCriticalPopulation", snapshot.population.critical)
    root:SetAttribute("ObservedStockTotal", snapshot.stocks.Total)
    root:SetAttribute("ObservedStructureCount", snapshot.structureCount)
    root:SetAttribute("ObservedResourceCount", snapshot.resourceCount)
    root:SetAttribute("LivingWorldReady", snapshot.signals.livingWorldReady)
    root:SetAttribute("BiomeReady", snapshot.signals.biomeReady)
    K0Verifier.Run()
end

local agentState = SourceReader.AgentState()
if agentState then
    lastAgentTick = agentState:GetAttribute("WorldTick") or 0
    agentState:GetAttributeChangedSignal("WorldTick"):Connect(function()
        local tick = agentState:GetAttribute("WorldTick") or 0
        if tick ~= lastAgentTick then
            lastAgentTick = tick
            publish()
        end
    end)
end

local function attachLivingWorld()
    local living = SourceReader.LivingWorldState()
    if not living then return false end
    lastLivingTick = living:GetAttribute("LivingWorldTick") or 0
    living:GetAttributeChangedSignal("LivingWorldTick"):Connect(function()
        local tick = living:GetAttribute("LivingWorldTick") or 0
        if tick ~= lastLivingTick then
            lastLivingTick = tick
            publish()
        end
    end)
    return true
end

if not attachLivingWorld() then
    workspace.ChildAdded:Connect(function(child)
        if child.Name == Contract.LivingWorldStateName and child:IsA("Folder") then
            attachLivingWorld()
            publish()
        end
    end)
end

publish()
print("[AstraLife] Kingdom K0 core online: read-only adapters + isolated write boundary")

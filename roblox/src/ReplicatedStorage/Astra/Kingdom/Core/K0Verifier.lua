local Contract = require(script.Parent.Contract)
local SourceReader = require(script.Parent.SourceReader)
local StateWriter = require(script.Parent.StateWriter)

local K0Verifier = {}

function K0Verifier.Run()
    local root = StateWriter.Root()
    local failures = {}

    for domain, owns in pairs(Contract.Ownership) do
        if owns ~= false then table.insert(failures, "ownership:" .. domain) end
        if root:GetAttribute("Owns" .. domain) ~= false then table.insert(failures, "attr:" .. domain) end
    end

    if root.Parent ~= workspace then table.insert(failures, "state_root_parent") end
    if root.Name ~= Contract.StateRootName then table.insert(failures, "state_root_name") end

    local cadence = SourceReader.ReadCadence()
    if not cadence.hasAgentClock then table.insert(failures, "agent_world_state_missing") end

    local snapshot = SourceReader.Snapshot()
    if type(snapshot.stocks) ~= "table" then table.insert(failures, "stock_adapter") end
    if type(snapshot.population) ~= "table" then table.insert(failures, "population_adapter") end
    if type(snapshot.signals) ~= "table" then table.insert(failures, "signal_adapter") end

    local status = #failures == 0 and "PASS" or "RUNNING"
    root:SetAttribute("K0Status", status)
    root:SetAttribute("K0Failures", table.concat(failures, ","))
    root:SetAttribute("K0AgentTick", cadence.agentTick)
    root:SetAttribute("K0LivingWorldTick", cadence.livingWorldTick)
    root:SetAttribute("K0LivingWorldDetected", cadence.hasLivingWorldClock)
    return status == "PASS", failures
end

return K0Verifier

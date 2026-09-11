local Contract = require(script.Parent.Contract)

local SourceReader = {}

local function folder(name)
    local value = workspace:FindFirstChild(name)
    return value and value:IsA("Folder") and value or nil
end

function SourceReader.AgentState()
    return folder(Contract.AgentStateName)
end

function SourceReader.LivingWorldState()
    return folder(Contract.LivingWorldStateName)
end

function SourceReader.Agents()
    return folder("AstraAgents")
end

function SourceReader.Structures()
    return folder("AstraStructures")
end

function SourceReader.ReadCadence()
    local agentState = SourceReader.AgentState()
    local living = SourceReader.LivingWorldState()
    return {
        agentTick = agentState and (agentState:GetAttribute("WorldTick") or 0) or 0,
        livingWorldTick = living and (living:GetAttribute("LivingWorldTick") or 0) or 0,
        livingWorldVersion = living and (living:GetAttribute("Version") or "None") or "None",
    }
end

function SourceReader.ReadStocks()
    local state = SourceReader.AgentState()
    local out = { Wood = 0, Stone = 0, Food = 0, Water = 0, Total = 0, Capacity = 0 }
    if not state then return out end
    for _, item in ipairs({"Wood", "Stone", "Food", "Water"}) do
        out[item] = state:GetAttribute("Stock_" .. item) or 0
    end
    out.Total = state:GetAttribute("StockTotal") or (out.Wood + out.Stone + out.Food + out.Water)
    out.Capacity = state:GetAttribute("StorageCapacity") or 0
    return out
end

function SourceReader.ReadIntegrationSignals()
    local living = SourceReader.LivingWorldState()
    return {
        w6Ready = living and living:GetAttribute("W6Status") == "PASS" or false,
        w7Ready = living and living:GetAttribute("W7Status") == "PASS" or false,
        worldVersion = living and living:GetAttribute("Version") or "None",
        worldTransactionsOwnedExternally = true,
        navigationOwnedExternally = true,
    }
end

function SourceReader.Snapshot()
    return {
        cadence = SourceReader.ReadCadence(),
        stocks = SourceReader.ReadStocks(),
        integration = SourceReader.ReadIntegrationSignals(),
        agentCount = SourceReader.Agents() and #SourceReader.Agents():GetChildren() or 0,
        structureCount = SourceReader.Structures() and #SourceReader.Structures():GetChildren() or 0,
    }
end

return SourceReader

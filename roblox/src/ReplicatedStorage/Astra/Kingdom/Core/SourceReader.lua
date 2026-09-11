local Contract = require(script.Parent.Contract)

local SourceReader = {}

local function findFolder(name)
    local value = workspace:FindFirstChild(name)
    return value and value:IsA("Folder") and value or nil
end

local function countModels(folder)
    if not folder then return 0 end
    local count = 0
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then count += 1 end
    end
    return count
end

function SourceReader.AgentState()
    return findFolder(Contract.AgentStateName)
end

function SourceReader.LivingWorldState()
    return findFolder(Contract.LivingWorldStateName)
end

function SourceReader.Agents()
    return findFolder("AstraAgents")
end

function SourceReader.Resources()
    return findFolder("AstraResources")
end

function SourceReader.Structures()
    return findFolder("AstraStructures")
end

function SourceReader.ReadCadence()
    local agentState = SourceReader.AgentState()
    local livingState = SourceReader.LivingWorldState()
    return {
        agentTick = agentState and (agentState:GetAttribute("WorldTick") or 0) or 0,
        livingWorldTick = livingState and (livingState:GetAttribute("LivingWorldTick") or 0) or 0,
        hasAgentClock = agentState ~= nil,
        hasLivingWorldClock = livingState ~= nil,
    }
end

function SourceReader.ReadStocks()
    local state = SourceReader.AgentState()
    return {
        Wood = state and (state:GetAttribute("Stock_Wood") or 0) or 0,
        Stone = state and (state:GetAttribute("Stock_Stone") or 0) or 0,
        Food = state and (state:GetAttribute("Stock_Food") or 0) or 0,
        Water = state and (state:GetAttribute("Stock_Water") or 0) or 0,
        Total = state and (state:GetAttribute("StockTotal") or 0) or 0,
        Capacity = state and (state:GetAttribute("StorageCapacity") or 0) or 0,
    }
end

function SourceReader.ReadPopulation()
    local agents = SourceReader.Agents()
    local total, critical = countModels(agents), 0
    local safetyTotal, socialTotal, healthRatioTotal = 0, 0, 0
    if agents then
        for _, agent in ipairs(agents:GetChildren()) do
            if agent:IsA("Model") then
                if agent:GetAttribute("SurvivalCritical") == true then critical += 1 end
                safetyTotal += agent:GetAttribute("Safety") or 100
                socialTotal += agent:GetAttribute("Social") or 100
                local humanoid = agent:FindFirstChildOfClass("Humanoid")
                healthRatioTotal += humanoid and humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) or 1
            end
        end
    end
    local divisor = math.max(1, total)
    return {
        total = total,
        critical = critical,
        averageSafety = safetyTotal / divisor,
        averageSocial = socialTotal / divisor,
        averageHealthRatio = healthRatioTotal / divisor,
    }
end

function SourceReader.ReadWorldSignals()
    local agentState = SourceReader.AgentState()
    local livingState = SourceReader.LivingWorldState()
    return {
        dangerActive = agentState and agentState:GetAttribute("DangerActive") == true or false,
        weather = agentState and agentState:GetAttribute("Weather") or nil,
        dayPhase = agentState and agentState:GetAttribute("DayPhase") or nil,
        livingWorldReady = livingState and livingState:GetAttribute("W0Status") == "PASS" or false,
        biomeReady = livingState and livingState:GetAttribute("W1Status") == "PASS" or false,
    }
end

function SourceReader.Snapshot()
    return {
        cadence = SourceReader.ReadCadence(),
        stocks = SourceReader.ReadStocks(),
        population = SourceReader.ReadPopulation(),
        signals = SourceReader.ReadWorldSignals(),
        structureCount = SourceReader.Structures() and #SourceReader.Structures():GetChildren() or 0,
        resourceCount = SourceReader.Resources() and #SourceReader.Resources():GetChildren() or 0,
    }
end

return SourceReader

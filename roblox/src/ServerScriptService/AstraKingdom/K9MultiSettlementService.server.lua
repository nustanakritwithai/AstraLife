local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local Economy = require(Kingdom.K9.MultiSettlementEconomy)
local Verifier = require(Kingdom.K9.K9Verifier)

local scope = StateWriter.Scope("K9MultiSettlement")
scope:SetAttribute("Version", "K9-0.1")
scope:SetAttribute("OwnsSettlements", false)
scope:SetAttribute("OwnsStock", false)
scope:SetAttribute("ProjectionOnly", true)

local function ensureChild(parent, name)
    local found = parent:FindFirstChild(name)
    if found and found:IsA("Folder") then return found end
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local function readSettlements()
    local result = {}
    local source = workspace:FindFirstChild("AstraSettlements")
    if source then
        for _, s in ipairs(source:GetChildren()) do
            if s:IsA("Folder") or s:IsA("Model") then
                local stocks = {}
                for _, good in ipairs({ "Food", "Water", "Wood", "Stone" }) do
                    stocks[good] = s:GetAttribute("Stock_" .. good) or 0
                end
                table.insert(result, {
                    id = s:GetAttribute("SettlementId") or s.Name,
                    population = s:GetAttribute("Population") or 1,
                    infrastructure = s:GetAttribute("Infrastructure") or 0,
                    stocks = stocks,
                })
            end
        end
    end
    if #result == 0 then
        local snap = SourceReader.Snapshot()
        table.insert(result, {
            id = "colony-main",
            population = snap.population.total,
            infrastructure = snap.structureCount,
            stocks = snap.stocks,
        })
    end
    table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return result
end

local lastTick = -1
local function run()
    local tick = SourceReader.ReadCadence().agentTick
    if tick == lastTick then return end
    lastTick = tick
    local beforeStocks = SourceReader.ReadStocks()
    local projected = Economy.Project(readSettlements())
    local summary = Economy.WorldSummary(projected)

    local projectedRoot = ensureChild(scope, "Settlements")
    local keep = {}
    for _, s in ipairs(projected) do
        local id = tostring(s.id)
        keep[id] = true
        local node = ensureChild(projectedRoot, id)
        node:SetAttribute("Population", s.population)
        node:SetAttribute("Prosperity", math.floor(s.prosperity * 10 + 0.5) / 10)
        node:SetAttribute("ScarcityAverage", math.floor(s.scarcityAverage * 1000 + 0.5) / 1000)
        node:SetAttribute("State", s.state)
        for good, data in pairs(s.goods) do
            node:SetAttribute("Stock_" .. good, data.stock)
            node:SetAttribute("Demand_" .. good, data.demand)
            node:SetAttribute("Coverage_" .. good, data.coverage)
            node:SetAttribute("Scarcity_" .. good, data.scarcity)
            node:SetAttribute("Price_" .. good, data.price)
        end
    end
    for _, child in ipairs(projectedRoot:GetChildren()) do
        if not keep[child.Name] then child:Destroy() end
    end

    StateWriter.SetMany(scope, {
        LastProcessedTick = tick,
        SettlementCount = summary.settlementCount,
        TotalPopulation = summary.totalPopulation,
        CrisisCount = summary.crisisCount,
        AverageProsperity = summary.averageProsperity,
        AverageScarcity = summary.averageScarcity,
    })
    Verifier.Verify(scope, beforeStocks, SourceReader.ReadStocks(), summary)
end

local agentState = SourceReader.AgentState()
if agentState then agentState:GetAttributeChangedSignal("WorldTick"):Connect(run) end
run()

print("[AstraKingdom] K9 Multi-Settlement Economy attached")

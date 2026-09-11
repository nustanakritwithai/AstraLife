local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kingdom = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Kingdom")
local SourceReader = require(Kingdom.Core.SourceReader)
local StateWriter = require(Kingdom.Core.StateWriter)
local TradeContracts = require(Kingdom.K8.TradeContracts)
local Verifier = require(Kingdom.K8.K8Verifier)

local scope = StateWriter.Scope("K8TradeContracts")
scope:SetAttribute("Version", "K8-0.1")
scope:SetAttribute("OwnsRoutes", false)
scope:SetAttribute("OwnsStock", false)
scope:SetAttribute("OwnsAgentMovement", false)

local lastTick = -1

local function readSettlements()
    local result = {}
    local folder = workspace:FindFirstChild("AstraSettlements")
    if folder then
        for _, s in ipairs(folder:GetChildren()) do
            if s:IsA("Folder") or s:IsA("Model") then
                local stocks, prices, targets = {}, {}, {}
                for _, good in ipairs({ "Food", "Water", "Wood", "Stone" }) do
                    stocks[good] = s:GetAttribute("Stock_" .. good) or 0
                    prices[good] = s:GetAttribute("Price_" .. good) or 1
                    targets[good] = s:GetAttribute("Target_" .. good) or math.max(4, (s:GetAttribute("Population") or 1) * 2)
                end
                table.insert(result, {
                    id = s:GetAttribute("SettlementId") or s.Name,
                    population = s:GetAttribute("Population") or 1,
                    stocks = stocks,
                    prices = prices,
                    targets = targets,
                })
            end
        end
    end

    if #result == 0 then
        local snap = SourceReader.Snapshot()
        table.insert(result, {
            id = "colony-main",
            population = snap.population.total,
            stocks = snap.stocks,
            prices = { Food = 4, Water = 3, Wood = 5, Stone = 7 },
            targets = {
                Food = math.max(4, snap.population.total * 2),
                Water = math.max(4, snap.population.total * 2),
                Wood = math.max(4, snap.population.total * 1.5),
                Stone = math.max(4, snap.population.total * 1.2),
            },
        })
    end

    table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return result
end

local function routeQuote(a, b)
    local living = SourceReader.LivingWorldState()
    if not living then return { cost = 0, risk = 0 } end
    local prefix = "Route_" .. tostring(a) .. "_" .. tostring(b) .. "_"
    return {
        cost = living:GetAttribute(prefix .. "Cost") or 0,
        risk = living:GetAttribute(prefix .. "Risk") or 0,
    }
end

local function run()
    local snap = SourceReader.Snapshot()
    local tick = snap.cadence.agentTick
    if tick == lastTick then return end
    lastTick = tick

    local beforeStocks = SourceReader.ReadStocks()
    local proposals = TradeContracts.Evaluate(readSettlements(), routeQuote)
    local summary = TradeContracts.Summary(proposals)

    StateWriter.SetMany(scope, {
        LastProcessedTick = tick,
        SettlementCount = #readSettlements(),
        ProposalCount = summary.proposalCount,
        ViableCount = summary.viableCount,
        TotalExpectedProfit = summary.totalExpectedProfit,
        TopContractId = summary.topContractId,
        TopGood = summary.topGood,
        TopExpectedProfit = summary.topExpectedProfit,
        State = summary.viableCount > 0 and "OPPORTUNITIES" or "IDLE",
    })

    local afterStocks = SourceReader.ReadStocks()
    Verifier.Verify(scope, beforeStocks, afterStocks, summary)
end

local agentState = SourceReader.AgentState()
if agentState then agentState:GetAttributeChangedSignal("WorldTick"):Connect(run) end
run()

print("[AstraKingdom] K8 Trade Contracts attached")

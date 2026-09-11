local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Kingdom = Astra:WaitForChild("Kingdom")
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)
local MarketEconomy = require(Kingdom.MarketEconomy)
local LaborMarket = require(Kingdom.LaborMarket)
local SettlementState = require(Kingdom.SettlementState)
local Organization = require(Kingdom.Organization)
local Governance = require(Kingdom.Governance)
local Recruitment = require(Kingdom.Recruitment)
local MigrationPressure = require(Kingdom.MigrationPressure)
local Verifier = require(Kingdom.Verifier)

local folders = WorldState.Ensure(Config)

local function ensureFolder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then return existing end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local root = ensureFolder(workspace, "AstraKingdomState")
local market = ensureFolder(root, "Market")
local labor = ensureFolder(root, "Labor")
local settlement = ensureFolder(root, "Settlement")
local organization = ensureFolder(root, "Organization")
local governance = ensureFolder(root, "Governance")
local recruitment = ensureFolder(root, "Recruitment")
local migration = ensureFolder(root, "Migration")

root:SetAttribute("Version", "KingdomSocietyAdapter-0.1")
root:SetAttribute("SourceReference", "Kingdom-sandbox")
root:SetAttribute("OwnsWorldClock", false)
root:SetAttribute("OwnsWorldGrid", false)
root:SetAttribute("OwnsTerrain", false)
root:SetAttribute("OwnsSkills", false)
root:SetAttribute("OwnsAgentGoals", false)
root:SetAttribute("Authority", "read-only socio-economic projection")

local lastProcessedTick = -1

local function processTick(tick)
    if tick <= lastProcessedTick then return end
    lastProcessedTick = tick

    local economy = MarketEconomy.Update(folders, market)
    local laborResult = LaborMarket.Update(market, labor)
    local settlementResult = SettlementState.Update(folders, market, settlement)
    Organization.Update(folders, settlement, organization)
    local governanceResult = Governance.Update(settlement, organization, governance)
    local recruitmentResult = Recruitment.Update(organization, settlement, labor, recruitment)
    local migrationResult = MigrationPressure.Update(folders, market, settlement, migration)

    root:SetAttribute("LastProcessedTick", tick)
    root:SetAttribute("TradeHealth", math.floor((economy.tradeHealth or 0) * 10 + 0.5) / 10)
    root:SetAttribute("HighestDemandProfession", laborResult.profession or "None")
    root:SetAttribute("SettlementStability", settlementResult.Stability or 0)
    root:SetAttribute("GovernanceLegitimacy", math.floor((governanceResult.legitimacy or 0) * 1000 + 0.5) / 10)
    root:SetAttribute("RecruitmentNeedRole", recruitmentResult.role or "None")
    root:SetAttribute("MigrationCandidateCount", migrationResult.candidates or 0)
    root:SetAttribute("Status", "ONLINE")
    Verifier.Update(root, folders.state)
end

local function scheduleTick()
    local tick = folders.state:GetAttribute("WorldTick") or 0
    task.defer(function()
        local ok, err = pcall(processTick, tick)
        if not ok then
            root:SetAttribute("Status", "ERROR")
            root:SetAttribute("LastError", tostring(err))
            folders.state:SetAttribute("KingdomAdapterStatus", "ERROR")
            warn("[AstraKingdom]", err)
        else
            root:SetAttribute("LastError", "")
        end
    end)
end

folders.state:GetAttributeChangedSignal("WorldTick"):Connect(scheduleTick)
if (folders.state:GetAttribute("WorldTick") or 0) > 0 then scheduleTick() end

print("[AstraLife] Kingdom society/economy adapter online — no WorldSim or P7 ownership")

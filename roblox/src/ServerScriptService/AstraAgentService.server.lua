local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Brain = require(Astra.BrainIntegrated)
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)
local SharedKnowledge = require(Astra.SharedKnowledge)
local Communication = require(Astra.Communication)
local WorldSimulation = require(Astra.WorldSimulation)
local RoleSystem = require(Astra.RoleSystem)
local SkillLearning = require(Astra.SkillLearning)
local P2Verifier = require(Astra.P2Verifier)
local P3Verifier = require(Astra.P3Verifier)
local P4Verifier = require(Astra.P4Verifier)
local P5Verifier = require(Astra.P5Verifier)
local P6Verifier = require(Astra.P6Verifier)
local P7Verifier = require(Astra.P7Verifier)
local ScaleVerifier = require(Astra.ScaleVerifier)
local IntegrationVerifier = require(Astra.IntegrationVerifier)

local EcosystemService = require(script.Parent.AstraWorld.EcosystemService)
local SurvivalBridgeService = require(script.Parent.AstraWorld.SurvivalBridgeService)

local folders = WorldState.Ensure(Config)
local started = setmetatable({}, { __mode = "k" })
local scheduled = setmetatable({}, { __mode = "k" })

local livingWorld = EcosystemService.Start()
local livingState = livingWorld.runtime.state
livingState:SetAttribute("W7AgentIntegrated", true)
livingState:SetAttribute("W6BrainIntegrated", true)
folders.state:SetAttribute("P75W7IntegrationStatus", "RUNNING")
-- I6: set before scheduling brains so SkillLearning/Brain see outcome-only mode.
folders.state:SetAttribute("P7_I6OutcomeOnly", true)
folders.state:SetAttribute("ScaleRuntimeError", false)

WorldSimulation.Initialize(folders, Config)
RoleSystem.Initialize(folders, Config)
SkillLearning.Initialize(folders, Config)

local function startAgent(agent)
    if started[agent] or not agent:IsA("Model") then return end
    local humanoid = agent:FindFirstChildOfClass("Humanoid")
    local root = agent:FindFirstChild("HumanoidRootPart")
    local head = agent:FindFirstChild("Head")
    if not humanoid or not root or not head then return end

    local tick = WorldState.GetTick(Config)
    RoleSystem.PrepareAgent(agent, folders, Config, tick)
    SkillLearning.PrepareAgent(agent, Config)
    started[agent] = true
    Brain.Start(agent, { survivalBridge = SurvivalBridgeService })
    agent:SetAttribute("ScaleBrainStarted", true)
end

local function scheduleAgent(agent, fallbackIndex)
    if scheduled[agent] or started[agent] or not agent:IsA("Model") then return end
    scheduled[agent] = true

    local phase = agent:GetAttribute("DecisionPhaseSeconds")
    if phase == nil then
        local index = agent:GetAttribute("ScaleIndex") or fallbackIndex or 1
        phase = math.max(0, (index - 1) * Config.DecisionStaggerStepSeconds)
        agent:SetAttribute("DecisionPhaseSeconds", phase)
    end

    task.delay(phase, function()
        if agent.Parent then startAgent(agent) end
    end)
end

local existing = {}
for _, agent in ipairs(folders.agents:GetChildren()) do
    if agent:IsA("Model") then table.insert(existing, agent) end
end
table.sort(existing, function(a, b)
    return (a:GetAttribute("ScaleIndex") or 999) < (b:GetAttribute("ScaleIndex") or 999)
end)
for index, agent in ipairs(existing) do scheduleAgent(agent, index) end

folders.agents.ChildAdded:Connect(function(agent)
    task.wait(0.05)
    scheduleAgent(agent, agent:GetAttribute("ScaleIndex") or #folders.agents:GetChildren())
end)

local function safeStep(name, callback)
    local ok, err = pcall(callback)
    if not ok then
        folders.state:SetAttribute("ScaleRuntimeError", true)
        folders.state:SetAttribute("ScaleLastRuntimeErrorSystem", name)
        folders.state:SetAttribute("ScaleLastRuntimeError", tostring(err))
        folders.state:SetAttribute("P75W7IntegrationStatus", "ERROR")
        warn("[AstraLife][P75W7]", name, err)
    end
end

-- I0.3: composed-runtime status from live evidence, not startup verifier PASS.
local integrationVerifier = IntegrationVerifier.new()

local function updateIntegrationStatus()
    local status, evidence = integrationVerifier:Update(
        livingState, folders.state, Config, livingWorld.runtime.clock.tick
    )
    folders.state:SetAttribute("P75W7IntegrationStatus", status)

    local failing = {}
    for name, value in pairs(evidence) do
        if type(value) == "boolean" then
            folders.state:SetAttribute("I0_" .. name, value)
            if not value then table.insert(failing, name) end
        end
    end
    folders.state:SetAttribute("I0_FailingEvidence", #failing > 0 and table.concat(failing, ",") or "none")
end

livingWorld.runtime.clock:RegisterSystem("P75.ColonyAuthority", Config.LivingWorldDecisionTicks or 8, function()
    local tick = WorldState.NextTick(Config)

    safeStep("SharedKnowledge", function()
        local expired = SharedKnowledge.Cleanup(tick)
        folders.state:SetAttribute("ExpiredSharedKnowledge", (folders.state:GetAttribute("ExpiredSharedKnowledge") or 0) + expired)
        folders.state:SetAttribute("KnownResourceCount", SharedKnowledge.ActiveCount(tick))
    end)

    safeStep("Communication", function()
        local removed = Communication.Cleanup(tick, Config)
        folders.state:SetAttribute("ScaleMessagesCleaned", (folders.state:GetAttribute("ScaleMessagesCleaned") or 0) + removed)
    end)

    safeStep("WorldSimulation", function() WorldSimulation.Tick(folders, tick, Config) end)
    safeStep("RoleSystem", function() RoleSystem.Tick(folders, tick, Config) end)
    safeStep("SkillLearning", function()
        SkillLearning.Tick(folders, tick, Config)
        SkillLearning.SyncAll(folders, Config)
    end)

    safeStep("P2Verifier", function() P2Verifier.Update(folders.state) end)
    safeStep("P3Verifier", function() P3Verifier.Update(folders.state) end)
    safeStep("P4Verifier", function() P4Verifier.Update(folders.state) end)
    safeStep("P5Verifier", function() P5Verifier.Update(folders.state) end)
    safeStep("P6Verifier", function() P6Verifier.Update(folders.state) end)
    safeStep("P7Verifier", function() P7Verifier.Update(folders.state) end)
    safeStep("ScaleVerifier", function() ScaleVerifier.Update(folders, tick, Config) end)
    safeStep("IntegrationStatus", updateIntegrationStatus)
end, 850)

print("[AstraLife] Agent service online - P7.5 Scale12 + W7 Ecosystem integration")

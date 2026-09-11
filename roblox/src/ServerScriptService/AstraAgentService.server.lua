local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Brain = require(Astra.Brain)
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)
local SharedKnowledge = require(Astra.SharedKnowledge)
local WorldSimulation = require(Astra.WorldSimulation)
local RoleSystem = require(Astra.RoleSystem)
local SkillLearning = require(Astra.SkillLearning)
local P2Verifier = require(Astra.P2Verifier)
local P3Verifier = require(Astra.P3Verifier)
local P4Verifier = require(Astra.P4Verifier)
local P5Verifier = require(Astra.P5Verifier)
local P6Verifier = require(Astra.P6Verifier)
local P7Verifier = require(Astra.P7Verifier)
local SurvivalBridgeService = require(script.Parent.AstraWorld.SurvivalBridgeService)

local folders = WorldState.Ensure(Config)
local started = setmetatable({}, { __mode = "k" })
local livingWorld = SurvivalBridgeService.Start()
livingWorld.runtime.state:SetAttribute("W6BrainIntegrated", true)

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
    Brain.Start(agent)
end

for _, agent in ipairs(folders.agents:GetChildren()) do
    startAgent(agent)
end

folders.agents.ChildAdded:Connect(function(agent)
    task.wait(0.25)
    startAgent(agent)
end)

-- One authoritative colony/world clock for TTL, environment, roles, learning and verification.
task.spawn(function()
    while true do
        task.wait(Config.TickSeconds)
        local tick = WorldState.NextTick(Config)
        local expired = SharedKnowledge.Cleanup(tick)
        folders.state:SetAttribute("ExpiredSharedKnowledge", (folders.state:GetAttribute("ExpiredSharedKnowledge") or 0) + expired)
        folders.state:SetAttribute("KnownResourceCount", SharedKnowledge.ActiveCount(tick))

        WorldSimulation.Tick(folders, tick, Config)
        RoleSystem.Tick(folders, tick, Config)
        SkillLearning.Tick(folders, tick, Config)
        SkillLearning.SyncAll(folders, Config)

        P2Verifier.Update(folders.state)
        P3Verifier.Update(folders.state)
        P4Verifier.Update(folders.state)
        P5Verifier.Update(folders.state)
        P6Verifier.Update(folders.state)
        P7Verifier.Update(folders.state)
    end
end)

print("[AstraLife] Agent service online - P7 Skill Learning + W6 Living World Bridge")

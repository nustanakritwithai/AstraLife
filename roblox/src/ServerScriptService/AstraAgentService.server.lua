local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Brain = require(Astra.Brain)
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)

local folders = WorldState.Ensure()

local started = setmetatable({}, { __mode = "k" })

local function startAgent(agent)
    if started[agent] or not agent:IsA("Model") then
        return
    end

    local humanoid = agent:FindFirstChildOfClass("Humanoid")
    local root = agent:FindFirstChild("HumanoidRootPart")
    local head = agent:FindFirstChild("Head")

    if not humanoid or not root or not head then
        return
    end

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

-- One shared world clock. Agents keep their own local decision ticks as well.
task.spawn(function()
    while true do
        task.wait(Config.TickSeconds)
        WorldState.NextTick()
    end
end)

print("[AstraLife] Agent service online")

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local worldState = workspace:WaitForChild("AstraWorldState")
local agents = workspace:WaitForChild("AstraAgents")

local gui = Instance.new("ScreenGui")
gui.Name = "AstraDebugUI"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(360, 250)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 34)
title.Position = UDim2.fromOffset(10, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(245, 248, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "AstraLife / Rojo"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Size = UDim2.new(1, -20, 0, 66)
summary.Position = UDim2.fromOffset(10, 44)
summary.BackgroundTransparency = 1
summary.Font = Enum.Font.Code
summary.TextSize = 16
summary.TextColor3 = Color3.fromRGB(210, 220, 235)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Parent = panel

local agentText = Instance.new("TextLabel")
agentText.Size = UDim2.new(1, -20, 1, -120)
agentText.Position = UDim2.fromOffset(10, 112)
agentText.BackgroundTransparency = 1
agentText.Font = Enum.Font.Code
agentText.TextSize = 14
agentText.TextColor3 = Color3.fromRGB(195, 210, 225)
agentText.TextXAlignment = Enum.TextXAlignment.Left
agentText.TextYAlignment = Enum.TextYAlignment.Top
agentText.TextWrapped = false
agentText.Parent = panel

local function update()
    summary.Text = string.format(
        "TeamResources: %d\nBuild: %s / %s / %d%% | WorldTick: %d",
        worldState:GetAttribute("TeamResources") or 0,
        worldState:GetAttribute("BuildStatus") or "Idle",
        worldState:GetAttribute("ActiveBuildId") or "None",
        worldState:GetAttribute("BuildProgress") or 0,
        worldState:GetAttribute("WorldTick") or 0
    )

    local lines = {}
    for _, agent in ipairs(agents:GetChildren()) do
        if agent:IsA("Model") then
            table.insert(lines, string.format(
                "%s [%s]  Goal=%s  Energy=%s",
                agent.Name,
                agent:GetAttribute("Role") or "?",
                agent:GetAttribute("Goal") or "?",
                tostring(agent:GetAttribute("Energy") or "?")
            ))
        end
    end
    table.sort(lines)
    agentText.Text = table.concat(lines, "\n")
end

for _, attribute in ipairs({
    "TeamResources",
    "BuildStatus",
    "ActiveBuildId",
    "BuildProgress",
    "WorldTick",
}) do
    worldState:GetAttributeChangedSignal(attribute):Connect(update)
end

agents.ChildAdded:Connect(function()
    task.wait(0.2)
    update()
end)

agents.ChildRemoved:Connect(update)

task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        update()
    end
end)

update()

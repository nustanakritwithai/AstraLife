local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "AstraDebugGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(390, 300)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -16, 1, -16)
label.Position = UDim2.fromOffset(8, 8)
label.BackgroundTransparency = 1
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextColor3 = Color3.fromRGB(235, 242, 255)
label.Font = Enum.Font.Code
label.TextSize = 16
label.TextWrapped = false
label.Parent = panel

local function attr(instance, name, default)
    local value = instance and instance:GetAttribute(name)
    if value == nil then
        return default
    end
    return value
end

local function agentLine(agent)
    if not agent then
        return "-"
    end
    return string.format(
        "%s [%s] Goal=%s Carry=%s/%s",
        agent.Name,
        tostring(attr(agent, "Role", "?")),
        tostring(attr(agent, "Goal", "?")),
        tostring(attr(agent, "CarryTotal", 0)),
        tostring(attr(agent, "CarryCapacity", 0))
    )
end

while task.wait(0.5) do
    local state = workspace:FindFirstChild("AstraWorldState")
    local agents = workspace:FindFirstChild("AstraAgents")

    if not state then
        label.Text = "AstraLife: waiting for AstraWorldState..."
        continue
    end

    local scout = agents and agents:FindFirstChild("AstraScout")
    local gatherer = agents and agents:FindFirstChild("AstraGatherer")
    local builder = agents and agents:FindFirstChild("AstraBuilder")

    local lines = {
        "ASTRALIFE ROBLOX " .. tostring(attr(state, "Version", "?")),
        string.format("Tick: %s   P1: %s   P2: %s", attr(state, "WorldTick", 0), attr(state, "P1Status", "?"), attr(state, "P2Status", "?")),
        "",
        string.format("STOCK  Wood:%s  Stone:%s  Food:%s  Water:%s", attr(state, "Stock_Wood", 0), attr(state, "Stock_Stone", 0), attr(state, "Stock_Food", 0), attr(state, "Stock_Water", 0)),
        string.format("Storage: %s/%s", attr(state, "StockTotal", 0), attr(state, "StorageCapacity", 0)),
        string.format("Build: %s  %s%%", attr(state, "ActiveBuildId", "None"), attr(state, "BuildProgress", 0)),
        "",
        agentLine(scout),
        agentLine(gatherer),
        agentLine(builder),
        "",
        string.format("P1: sent=%s recv=%s belief75=%s remote=%s verify=%s collect=%s", tostring(attr(state, "P1_ScoutSent", false)), tostring(attr(state, "P1_GathererReceived", false)), tostring(attr(state, "P1_Belief75", false)), tostring(attr(state, "P1_RemoteGoal", false)), tostring(attr(state, "P1_Verified100", false)), tostring(attr(state, "P1_Collected", false))),
        string.format("P2: carry=%s deposit=%s recipe=%s storage=%s", tostring(attr(state, "P2_CarryObserved", false)), tostring(attr(state, "P2_DepositObserved", false)), tostring(attr(state, "P2_BuilderSpentRecipe", false)), tostring(attr(state, "P2_StorageReady", false))),
    }

    label.Text = table.concat(lines, "\n")
end

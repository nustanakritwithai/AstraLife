local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "AstraDebugGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "DebugPanel"
panel.Size = UDim2.fromOffset(360, 44)
panel.Position = UDim2.fromOffset(12, 12)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = gui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(280, 44)
sizeConstraint.MaxSize = Vector2.new(760, 520)
sizeConstraint.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Color3.fromRGB(22, 27, 38)
header.BackgroundTransparency = 0.02
header.BorderSizePixel = 0
header.Active = true
header.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 12)
headerCorner.Parent = header

local compactStatus = Instance.new("TextLabel")
compactStatus.Name = "CompactStatus"
compactStatus.Size = UDim2.new(1, -54, 1, 0)
compactStatus.Position = UDim2.fromOffset(10, 0)
compactStatus.BackgroundTransparency = 1
compactStatus.TextXAlignment = Enum.TextXAlignment.Left
compactStatus.TextYAlignment = Enum.TextYAlignment.Center
compactStatus.TextColor3 = Color3.fromRGB(235, 242, 255)
compactStatus.Font = Enum.Font.Code
compactStatus.TextSize = 13
compactStatus.TextTruncate = Enum.TextTruncate.AtEnd
compactStatus.Text = "ASTRA DEBUG | waiting..."
compactStatus.Parent = header

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "Toggle"
toggleButton.Size = UDim2.fromOffset(40, 32)
toggleButton.Position = UDim2.new(1, -46, 0, 6)
toggleButton.BackgroundColor3 = Color3.fromRGB(38, 45, 62)
toggleButton.BorderSizePixel = 0
toggleButton.TextColor3 = Color3.fromRGB(245, 248, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 22
toggleButton.Text = "+"
toggleButton.AutoButtonColor = true
toggleButton.Parent = header

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.Size = UDim2.new(1, -12, 1, -56)
body.Position = UDim2.fromOffset(6, 50)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 5
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.CanvasSize = UDim2.fromOffset(0, 0)
body.Visible = false
body.Parent = panel

local label = Instance.new("TextLabel")
label.Name = "Details"
label.Size = UDim2.new(1, -8, 0, 700)
label.Position = UDim2.fromOffset(4, 0)
label.BackgroundTransparency = 1
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextColor3 = Color3.fromRGB(235, 242, 255)
label.Font = Enum.Font.Code
label.TextSize = 12
label.TextWrapped = false
label.Parent = body

local expanded = false
local expandedSize = UDim2.new(0.92, 0, 0, 520)
local collapsedSize = UDim2.fromOffset(360, 44)

local function setExpanded(value)
    expanded = value
    body.Visible = expanded
    toggleButton.Text = expanded and "−" or "+"
    panel.Size = expanded and expandedSize or collapsedSize
end

toggleButton.Activated:Connect(function()
    setExpanded(not expanded)
end)

-- Header drag works with both mouse and touch so the panel can be moved out of the way.
local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPosition = panel.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging or input ~= dragInput or not dragStart or not startPosition then
        return
    end

    local delta = input.Position - dragStart
    panel.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)

local function attr(instance, name, default)
    local value = instance and instance:GetAttribute(name)
    if value == nil then return default end
    return value
end

local function f1(value)
    return string.format("%.1f", tonumber(value) or 0)
end

local function agentLine(agent)
    return string.format(
        "%-18s %-8s G:%-16s C:%s/%s H:%s T:%s E:%s | S:%s G:%s B:%s XP:%s P:%.2f",
        agent.Name,
        tostring(attr(agent, "Role", "?")),
        tostring(attr(agent, "Goal", "?")),
        tostring(attr(agent, "CarryTotal", 0)),
        tostring(attr(agent, "CarryCapacity", 0)),
        tostring(attr(agent, "Hunger", "?")),
        tostring(attr(agent, "Thirst", "?")),
        tostring(attr(agent, "Energy", "?")),
        f1(attr(agent, "Skill_Scout", 0)),
        f1(attr(agent, "Skill_Gatherer", 0)),
        f1(attr(agent, "Skill_Builder", 0)),
        f1(attr(agent, "P7_XP_Total", 0)),
        tonumber(attr(agent, "DecisionPhaseSeconds", 0)) or 0
    )
end

local function sortedAgents(folder)
    local list = {}
    if folder then
        for _, agent in ipairs(folder:GetChildren()) do
            if agent:IsA("Model") then table.insert(list, agent) end
        end
    end
    table.sort(list, function(a, b)
        local ai = a:GetAttribute("ScaleIndex") or 999
        local bi = b:GetAttribute("ScaleIndex") or 999
        if ai == bi then return a.Name < b.Name end
        return ai < bi
    end)
    return list
end

setExpanded(false)

while task.wait(0.5) do
    local state = workspace:FindFirstChild("AstraWorldState")
    local agentsFolder = workspace:FindFirstChild("AstraAgents")
    if not state then
        compactStatus.Text = "ASTRA DEBUG | waiting for world..."
        label.Text = "AstraLife: waiting for AstraWorldState..."
        continue
    end

    compactStatus.Text = string.format(
        "ASTRA DEBUG  T:%s  P1:%s P2:%s P3:%s P4:%s P5:%s P6:%s P7:%s  SCALE:%s",
        attr(state, "WorldTick", 0),
        attr(state, "P1Status", "?"),
        attr(state, "P2Status", "?"),
        attr(state, "P3Status", "?"),
        attr(state, "P4Status", "?"),
        attr(state, "P5Status", "?"),
        attr(state, "P6Status", "?"),
        attr(state, "P7Status", "?"),
        attr(state, "Scale12Status", "?")
    )

    if expanded then
        local lines = {
            "ASTRALIFE ROBLOX " .. tostring(attr(state, "Version", "?")) .. "  |  12-AGENT SCALE TEST",
            string.format("Tick:%s  P1:%s P2:%s P3:%s P4:%s P5:%s P6:%s P7:%s  SCALE:%s", attr(state, "WorldTick", 0), attr(state, "P1Status", "?"), attr(state, "P2Status", "?"), attr(state, "P3Status", "?"), attr(state, "P4Status", "?"), attr(state, "P5Status", "?"), attr(state, "P6Status", "?"), attr(state, "P7Status", "?"), attr(state, "Scale12Status", "?")),
            string.format("WORLD %s %.1f  Weather:%s Event:%s Danger:%s", tostring(attr(state, "DayPhase", "?")), tonumber(attr(state, "ClockTime", 0)) or 0, tostring(attr(state, "Weather", "?")), tostring(attr(state, "WorldEvent", "None")), tostring(attr(state, "DangerActive", false))),
            string.format("SCALE Agents:%s/%s Online:%s Resources:%s  Roles S:%s/%s G:%s/%s B:%s/%s", attr(state, "ScaleAgentCount", 0), 12, attr(state, "ScaleOnlineAgents", 0), attr(state, "ScaleResourceCount", 0), attr(state, "ScaleRoleCount_Scout", 0), attr(state, "ScaleRoleTarget_Scout", 2), attr(state, "ScaleRoleCount_Gatherer", 0), attr(state, "ScaleRoleTarget_Gatherer", 7), attr(state, "ScaleRoleCount_Builder", 0), attr(state, "ScaleRoleTarget_Builder", 3)),
            string.format("LOAD Registry:%s peak:%s  Inbox:%s peak:%s  Stuck:%s peak:%s  Drops:%s  Phases:%s", attr(state, "ScaleMessageRegistry", 0), attr(state, "ScalePeakMessageRegistry", 0), attr(state, "ScaleInboxTotal", 0), attr(state, "ScalePeakInbox", 0), attr(state, "ScaleStuckAgents", 0), attr(state, "ScalePeakStuckAgents", 0), attr(state, "ScaleDroppedMessages", 0), attr(state, "ScaleDecisionPhaseCount", 0)),
            string.format("HEALTH queues:%s movement:%s roles:%s errors:%s  LongRun@500:%s", tostring(attr(state, "ScaleQueuesHealthy", false)), tostring(attr(state, "ScaleMovementHealthy", false)), tostring(attr(state, "ScaleRoleTargetHealthy", false)), tostring(attr(state, "ScaleRuntimeError", false)), tostring(attr(state, "Scale12LongRunStatus", "RUNNING"))),
            string.format("STOCK W:%s S:%s F:%s Wa:%s  Storage:%s/%s  Build:%s %s%% %s", attr(state, "Stock_Wood", 0), attr(state, "Stock_Stone", 0), attr(state, "Stock_Food", 0), attr(state, "Stock_Water", 0), attr(state, "StockTotal", 0), attr(state, "StorageCapacity", 0), attr(state, "ActiveBuildId", "None"), attr(state, "BuildProgress", 0), attr(state, "BuildStatus", "?")),
            "",
            "AGENTS",
        }

        for _, agent in ipairs(sortedAgents(agentsFolder)) do
            table.insert(lines, agentLine(agent))
        end

        table.insert(lines, "")
        table.insert(lines, string.format("P7 outcome:%s xp:%s skill:%s effect:%s antiGrind:%s", tostring(attr(state, "P7_OutcomeLearningObserved", false)), tostring(attr(state, "P7_XPRecorded", false)), tostring(attr(state, "P7_ActualSkillAdvanced", false)), tostring(attr(state, "P7_ActualEffectsReady", false)), tostring(attr(state, "P7_AntiGrindObserved", false))))

        label.Text = table.concat(lines, "\n")
        task.defer(function()
            local height = math.max(460, label.TextBounds.Y + 12)
            label.Size = UDim2.new(1, -8, 0, height)
            body.CanvasSize = UDim2.fromOffset(0, height + 8)
        end)
    end
end

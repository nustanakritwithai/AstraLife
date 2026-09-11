local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "AstraDebugGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "DebugPanel"
panel.Size = UDim2.fromOffset(390, 44)
panel.Position = UDim2.fromOffset(12, 12)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = gui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(300, 44)
sizeConstraint.MaxSize = Vector2.new(800, 580)
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
compactStatus.TextSize = 12
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
label.Size = UDim2.new(1, -8, 0, 760)
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
local expandedSize = UDim2.new(0.94, 0, 0, 560)
local collapsedSize = UDim2.fromOffset(390, 44)

local function setExpanded(value)
    expanded = value
    body.Visible = expanded
    toggleButton.Text = expanded and "−" or "+"
    panel.Size = expanded and expandedSize or collapsedSize
end

toggleButton.Activated:Connect(function()
    setExpanded(not expanded)
end)

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
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
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
    if not dragging or input ~= dragInput or not dragStart or not startPosition then return end
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

local function f2(value)
    return string.format("%.2f", tonumber(value) or 0)
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

local function agentLine(agent)
    return string.format(
        "%-18s %-8s G:%-15s C:%s/%s H:%s T:%s E:%s | S:%s G:%s B:%s XP:%s Path:%s | Dng:%s Haz:%s",
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
        tostring(attr(agent, "PathComputeCount", 0)),
        f2(attr(agent, "W6EnvironmentDanger", 0)),
        tostring(attr(agent, "W6DominantHazard", "?"))
    )
end

setExpanded(false)

while task.wait(0.5) do
    local state = workspace:FindFirstChild("AstraWorldState")
    local world = workspace:FindFirstChild("AstraLivingWorldState")
    local agentsFolder = workspace:FindFirstChild("AstraAgents")

    if not state then
        compactStatus.Text = "ASTRA DEBUG | waiting for colony..."
        label.Text = "AstraLife: waiting for AstraWorldState..."
        continue
    end

    compactStatus.Text = string.format(
        "T:%s P1-7:%s/%s/%s/%s/%s/%s/%s W0-7:%s/%s/%s/%s/%s/%s/%s/%s S:%s",
        attr(state, "WorldTick", 0),
        attr(state, "P1Status", "?"), attr(state, "P2Status", "?"), attr(state, "P3Status", "?"),
        attr(state, "P4Status", "?"), attr(state, "P5Status", "?"), attr(state, "P6Status", "?"), attr(state, "P7Status", "?"),
        attr(world, "W0Status", "?"), attr(world, "W1Status", "?"), attr(world, "W2Status", "?"), attr(world, "W3Status", "?"),
        attr(world, "W4Status", "?"), attr(world, "W5Status", "?"), attr(world, "W6Status", "?"), attr(world, "W7Status", "?"),
        attr(state, "Scale12Status", "?")
    )

    if expanded then
        local lines = {
            "ASTRALIFE ROBLOX " .. tostring(attr(state, "Version", "?")) .. " | P7.5 + W7 INTEGRATION",
            string.format("AGENT Tick:%s  P1:%s P2:%s P3:%s P4:%s P5:%s P6:%s P7:%s Scale:%s Long:%s", attr(state, "WorldTick", 0), attr(state, "P1Status", "?"), attr(state, "P2Status", "?"), attr(state, "P3Status", "?"), attr(state, "P4Status", "?"), attr(state, "P5Status", "?"), attr(state, "P6Status", "?"), attr(state, "P7Status", "?"), attr(state, "Scale12Status", "?"), attr(state, "Scale12LongRunStatus", "?")),
            string.format("WORLD Tick:%s Ver:%s W0:%s W1:%s W2:%s W3:%s W4:%s W5:%s W6:%s W7:%s", attr(world, "LivingWorldTick", 0), attr(world, "Version", "?"), attr(world, "W0Status", "?"), attr(world, "W1Status", "?"), attr(world, "W2Status", "?"), attr(world, "W3Status", "?"), attr(world, "W4Status", "?"), attr(world, "W5Status", "?"), attr(world, "W6Status", "?"), attr(world, "W7Status", "?")),
            string.format("CLIMATE %s %.1fh Season:%s Weather:%s Rain:%s Hum:%s", tostring(attr(world, "DayPhase", "?")), tonumber(attr(world, "ClimateHour", 0)) or 0, tostring(attr(world, "Season", "?")), tostring(attr(world, "Weather", "?")), f1(attr(world, "Precipitation", 0)), f1(attr(world, "Humidity", 0))),
            string.format("WORLD RES Food:%s Wood:%s Veg:%s Hydro:%s HazMax:%s Eco H/P/S:%s/%s/%s", f1(attr(world, "ResourceFoodTotal", 0)), f1(attr(world, "ResourceWoodTotal", 0)), f1(attr(world, "ResourceVegetationTotal", 0)), tostring(attr(world, "HydrologySteps", 0)), f1(attr(world, "HazardMaxDanger", 0)), f1(attr(world, "EcosystemHerbivores", 0)), f1(attr(world, "EcosystemPredators", 0)), f1(attr(world, "EcosystemScavengers", 0))),
            string.format("SCALE Agents:%s/%s Online:%s LegacyRes:%s Roles S:%s/%s G:%s/%s B:%s/%s", attr(state, "ScaleAgentCount", 0), 12, attr(state, "ScaleOnlineAgents", 0), attr(state, "ScaleResourceCount", 0), attr(state, "ScaleRoleCount_Scout", 0), attr(state, "ScaleRoleTarget_Scout", 2), attr(state, "ScaleRoleCount_Gatherer", 0), attr(state, "ScaleRoleTarget_Gatherer", 7), attr(state, "ScaleRoleCount_Builder", 0), attr(state, "ScaleRoleTarget_Builder", 3)),
            string.format("LOAD Registry:%s peak:%s Inbox:%s peak:%s Stuck:%s peak:%s Drops:%s Phases:%s", attr(state, "ScaleMessageRegistry", 0), attr(state, "ScalePeakMessageRegistry", 0), attr(state, "ScaleInboxTotal", 0), attr(state, "ScalePeakInbox", 0), attr(state, "ScaleStuckAgents", 0), attr(state, "ScalePeakStuckAgents", 0), attr(state, "ScaleDroppedMessages", 0), attr(state, "ScaleDecisionPhaseCount", 0)),
            string.format("BRIDGE eat:%s drink:%s harvest:%s colony:%s W6Tx:%s", tostring(attr(state, "W6_WorldEatObserved", false)), tostring(attr(state, "W6_WorldDrinkObserved", false)), tostring(attr(state, "W6_WorldHarvestObserved", false)), tostring(attr(state, "W6_WorldToColonyObserved", false)), tostring(attr(world, "W6TransactionsCommitted", 0))),
            string.format("I0 status:%s failing:%s", tostring(attr(state, "P75W7IntegrationStatus", "BOOTING")), tostring(attr(state, "I0_FailingEvidence", "none"))),
            "",
            "AGENTS",
        }

        for _, agent in ipairs(sortedAgents(agentsFolder)) do
            table.insert(lines, agentLine(agent))
        end

        table.insert(lines, "")
        table.insert(lines, string.format("P7 outcome:%s xp:%s skill:%s effect:%s antiGrind:%s", tostring(attr(state, "P7_OutcomeLearningObserved", false)), tostring(attr(state, "P7_XPRecorded", false)), tostring(attr(state, "P7_ActualSkillAdvanced", false)), tostring(attr(state, "P7_ActualEffectsReady", false)), tostring(attr(state, "P7_AntiGrindObserved", false))))
        table.insert(lines, string.format("INTEGRATION status:%s runtimeError:%s system:%s", tostring(attr(state, "P75W7IntegrationStatus", "BOOTING")), tostring(attr(state, "ScaleRuntimeError", false)), tostring(attr(state, "ScaleLastRuntimeErrorSystem", "None"))))

        label.Text = table.concat(lines, "\n")
        task.defer(function()
            local height = math.max(500, label.TextBounds.Y + 12)
            label.Size = UDim2.new(1, -8, 0, height)
            body.CanvasSize = UDim2.fromOffset(0, height + 8)
        end)
    end
end

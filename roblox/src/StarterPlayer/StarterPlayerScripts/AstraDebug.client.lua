local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "AstraDebugGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(760, 720)
panel.Position = UDim2.fromOffset(12, 12)
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
label.TextSize = 12
label.TextWrapped = false
label.Parent = panel

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

while task.wait(0.5) do
    local state = workspace:FindFirstChild("AstraWorldState")
    local agentsFolder = workspace:FindFirstChild("AstraAgents")
    if not state then
        label.Text = "AstraLife: waiting for AstraWorldState..."
        continue
    end

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
end

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "AstraDebugGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(680, 620)
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
label.TextSize = 13
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
    if not agent then return "-" end
    return string.format(
        "%s [%s] G=%s Carry=%s/%s H:%s T:%s E:%s Safe:%s Soc:%s",
        agent.Name,
        tostring(attr(agent, "Role", "?")),
        tostring(attr(agent, "Goal", "?")),
        tostring(attr(agent, "CarryTotal", 0)),
        tostring(attr(agent, "CarryCapacity", 0)),
        tostring(attr(agent, "Hunger", "?")),
        tostring(attr(agent, "Thirst", "?")),
        tostring(attr(agent, "Energy", "?")),
        tostring(attr(agent, "Safety", "?")),
        tostring(attr(agent, "Social", "?"))
    )
end

local function learningLine(agent)
    if not agent then return "-" end
    return string.format(
        "  Skill S:%s G:%s B:%s V:%s | XP:%s Last:%s x%s | Range:x%s Build:x%s Decay:x%s",
        f1(attr(agent, "Skill_Scout", 0)),
        f1(attr(agent, "Skill_Gatherer", 0)),
        f1(attr(agent, "Skill_Builder", 0)),
        f1(attr(agent, "Skill_Survival", 0)),
        f1(attr(agent, "P7_XP_Total", 0)),
        tostring(attr(agent, "P7LastLearningEvent", "None")),
        f1(attr(agent, "P7AntiGrindMultiplier", 1)),
        f1(attr(agent, "P7_ResourceRangeMultiplier", 1)),
        f1(attr(agent, "P7_BuildSpeedMultiplier", 1)),
        f1(attr(agent, "P7_SurvivalDecayMultiplier", 1))
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
        string.format("Tick:%s P1:%s P2:%s P3:%s P4:%s P5:%s P6:%s P7:%s", attr(state, "WorldTick", 0), attr(state, "P1Status", "?"), attr(state, "P2Status", "?"), attr(state, "P3Status", "?"), attr(state, "P4Status", "?"), attr(state, "P5Status", "?"), attr(state, "P6Status", "?"), attr(state, "P7Status", "?")),
        string.format("WORLD Phase:%s Clock:%.1f Weather:%s Event:%s Danger:%s", tostring(attr(state, "DayPhase", "?")), tonumber(attr(state, "ClockTime", 0)) or 0, tostring(attr(state, "Weather", "?")), tostring(attr(state, "WorldEvent", "None")), tostring(attr(state, "DangerActive", false))),
        "",
        string.format("STOCK Wood:%s Stone:%s Food:%s Water:%s", attr(state, "Stock_Wood", 0), attr(state, "Stock_Stone", 0), attr(state, "Stock_Food", 0), attr(state, "Stock_Water", 0)),
        string.format("Storage:%s/%s  Build:%s %s%% %s", attr(state, "StockTotal", 0), attr(state, "StorageCapacity", 0), attr(state, "ActiveBuildId", "None"), attr(state, "BuildProgress", 0), attr(state, "BuildStatus", "?")),
        string.format("Site W:%s/%s S:%s/%s Physical:%s", attr(state, "P3_Delivered_Wood", 0), attr(state, "P3_Required_Wood", 0), attr(state, "P3_Delivered_Stone", 0), attr(state, "P3_Required_Stone", 0), tostring(attr(state, "P3_PhysicalDelivery", false))),
        "",
        agentLine(scout), learningLine(scout),
        agentLine(gatherer), learningLine(gatherer),
        agentLine(builder), learningLine(builder),
        "",
        string.format("P1 sent:%s recv:%s belief:%s remote:%s verify:%s collect:%s", tostring(attr(state, "P1_ScoutSent", false)), tostring(attr(state, "P1_GathererReceived", false)), tostring(attr(state, "P1_Belief75", false)), tostring(attr(state, "P1_RemoteGoal", false)), tostring(attr(state, "P1_Verified100", false)), tostring(attr(state, "P1_Collected", false))),
        string.format("P2 carry:%s deposit:%s recipe:%s", tostring(attr(state, "P2_CarryObserved", false)), tostring(attr(state, "P2_DepositObserved", false)), tostring(attr(state, "P2_BuilderSpentRecipe", false))),
        string.format("P3 site:%s delivery:%s ready:%s wait:%s build:%s complete:%s", tostring(attr(state, "P3_SiteCreated", false)), tostring(attr(state, "P3_PhysicalDelivery", false)), tostring(attr(state, "P3_AllMaterialsDelivered", false)), tostring(attr(state, "P3_BuilderWaited", false)), tostring(attr(state, "P3_BuildProgress", false)), tostring(attr(state, "P3_BuildCompleted", false))),
        string.format("P4 needs:%s goal:%s eat:%s drink:%s rest:%s social:%s", tostring(attr(state, "P4_NeedsDecayed", false)), tostring(attr(state, "P4_SurvivalGoalObserved", false)), tostring(attr(state, "P4_EatObserved", false)), tostring(attr(state, "P4_DrinkObserved", false)), tostring(attr(state, "P4_RestObserved", false)), tostring(attr(state, "P4_SocialObserved", false))),
        string.format("P5 day:%s weather:%s event:%s regen:%s threat:%s needs:%s response:%s", tostring(attr(state, "P5_DayNightChanged", false)), tostring(attr(state, "P5_WeatherChanged", false)), tostring(attr(state, "P5_WorldEventTriggered", false)), tostring(attr(state, "P5_ResourceRegenerated", false)), tostring(attr(state, "P5_ThreatSpawned", false)), tostring(attr(state, "P5_WeatherAffectedNeeds", false)), tostring(attr(state, "P5_EnvironmentResponse", false))),
        string.format("P6 init:%s eval:%s skill:%s coverage:%s reassign:%s changed:%s", tostring(attr(state, "P6_InitialAssignment", false)), tostring(attr(state, "P6_RoleEvaluated", false)), tostring(attr(state, "P6_SkillUpdated", false)), tostring(attr(state, "P6_CoverageBalanced", false)), tostring(attr(state, "P6_ReassignmentReady", false)), tostring(attr(state, "P6_RoleChanged", false))),
        string.format("P7 init:%s outcome:%s xp:%s skill:%s effect:%s antiGrind:%s failure:%s buildLearn:%s", tostring(attr(state, "P7_LearningInitialized", false)), tostring(attr(state, "P7_OutcomeLearningObserved", false)), tostring(attr(state, "P7_XPRecorded", false)), tostring(attr(state, "P7_ActualSkillAdvanced", false)), tostring(attr(state, "P7_ActualEffectsReady", false)), tostring(attr(state, "P7_AntiGrindObserved", false)), tostring(attr(state, "P7_FailureLearningObserved", false)), tostring(attr(state, "P7_BuildCompletionLearned", false))),
    }

    label.Text = table.concat(lines, "\n")
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Astra = ReplicatedStorage:WaitForChild("Astra")
local Config = require(Astra.Config)
local WorldState = require(Astra.WorldState)
local ColonyEventFeed = require(Astra.ColonyEventFeed)

local folders = WorldState.Ensure(Config)
local feed = ColonyEventFeed.new(60)

local eventRemote = Astra:FindFirstChild("AstraEventFeed")
if not eventRemote then
    eventRemote = Instance.new("RemoteEvent")
    eventRemote.Name = "AstraEventFeed"
    eventRemote.Parent = Astra
end

local snapshotRemote = Astra:FindFirstChild("AstraEventFeedSnapshot")
if not snapshotRemote then
    snapshotRemote = Instance.new("RemoteFunction")
    snapshotRemote.Name = "AstraEventFeedSnapshot"
    snapshotRemote.Parent = Astra
end

local function worldTick()
    return folders.state:GetAttribute("WorldTick") or 0
end

local function publish(kind, text, severity, source)
    local event = feed:Push(worldTick(), kind, text, severity, source)
    if event then
        eventRemote:FireAllClients(event)
    end
end

snapshotRemote.OnServerInvoke = function()
    return feed:Snapshot(30)
end

local function watchAttribute(instance, attribute, callback)
    local previous = instance:GetAttribute(attribute)
    instance:GetAttributeChangedSignal(attribute):Connect(function()
        local current = instance:GetAttribute(attribute)
        if current == previous then
            return
        end
        local old = previous
        previous = current
        callback(current, old)
    end)
end

local function watchWorld()
    watchAttribute(folders.state, "Weather", function(current)
        if current then
            publish("weather", "สภาพอากาศเปลี่ยนเป็น " .. tostring(current), current == "Storm" and "warning" or "info", "world")
        end
    end)

    watchAttribute(folders.state, "DayPhase", function(current)
        if current then
            publish("day_phase", "ช่วงเวลาเปลี่ยนเป็น " .. tostring(current), "info", "world")
        end
    end)

    watchAttribute(folders.state, "WorldEvent", function(current)
        if current and current ~= "None" then
            publish("world_event", "World Event: " .. tostring(current), "warning", "world")
        end
    end)

    watchAttribute(folders.state, "DangerActive", function(current)
        if current == true then
            publish("danger", "ตรวจพบพื้นที่อันตราย", "critical", "world")
        elseif current == false then
            publish("danger", "พื้นที่อันตรายสงบลง", "success", "world")
        end
    end)

    watchAttribute(folders.state, "ActiveBuildId", function(current)
        if current and current ~= "None" then
            publish("construction", "เริ่มโครงการก่อสร้าง: " .. tostring(current), "info", "colony")
        end
    end)

    watchAttribute(folders.state, "BuildStatus", function(current)
        if current == "Completed" or current == "Complete" then
            local buildId = folders.state:GetAttribute("ActiveBuildId") or "Structure"
            publish("construction", "ก่อสร้างสำเร็จ: " .. tostring(buildId), "success", "colony")
        end
    end)
end

local watchedAgents = setmetatable({}, {__mode = "k"})

local function watchAgent(agent)
    if watchedAgents[agent] or not agent:IsA("Model") then
        return
    end
    watchedAgents[agent] = true

    local role = agent:GetAttribute("Role") or "Agent"
    publish("agent_join", agent.Name .. " ออนไลน์ในบทบาท " .. tostring(role), "info", agent.Name)

    watchAttribute(agent, "Goal", function(current, previous)
        if current and current ~= "" and current ~= previous then
            publish("goal", agent.Name .. " → " .. tostring(current), "info", agent.Name)
        end
    end)

    watchAttribute(agent, "SurvivalCritical", function(current)
        if current == true then
            publish("survival", agent.Name .. " เข้าสู่ภาวะวิกฤต", "critical", agent.Name)
        elseif current == false then
            publish("survival", agent.Name .. " พ้นภาวะวิกฤต", "success", agent.Name)
        end
    end)

    local humanoid = agent:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Died:Connect(function()
            publish("agent_down", agent.Name .. " เสียชีวิต", "critical", agent.Name)
        end)
    end
end

watchWorld()

for _, agent in ipairs(folders.agents:GetChildren()) do
    watchAgent(agent)
end

folders.agents.ChildAdded:Connect(function(agent)
    task.defer(watchAgent, agent)
end)

publish("system", "Colony Event Feed online", "success", "system")
print("[AstraLife] Colony Event Feed online")

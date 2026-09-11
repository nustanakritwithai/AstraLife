local PathfindingService = game:GetService("PathfindingService")

local Config = require(script.Parent.Config)
local WorldState = require(script.Parent.WorldState)
local Memory = require(script.Parent.Memory)
local Belief = require(script.Parent.Belief)
local Communication = require(script.Parent.Communication)
local Perception = require(script.Parent.Perception)
local Construction = require(script.Parent.Construction)
local Planner = require(script.Parent.Planner)

local Brain = {}

local runningAgents = setmetatable({}, { __mode = "k" })

local function inferRole(agent)
    local explicit = agent:GetAttribute("Role")
    if explicit and explicit ~= "" then
        return explicit
    end

    local name = string.lower(agent.Name)

    if string.find(name, "scout", 1, true) or string.find(agent.Name, "นักสำรวจ", 1, true) then
        return Config.Roles.Scout
    elseif string.find(name, "gather", 1, true) or string.find(agent.Name, "เก็บ", 1, true) then
        return Config.Roles.Gatherer
    elseif string.find(name, "builder", 1, true) or string.find(agent.Name, "ก่อสร้าง", 1, true) then
        return Config.Roles.Builder
    end

    return Config.Roles.Explorer
end

local function createThoughtBubble(agent, head)
    local old = head:FindFirstChild("AstraThought")
    if old then
        old:Destroy()
    end

    local gui = Instance.new("BillboardGui")
    gui.Name = "AstraThought"
    gui.Size = UDim2.fromOffset(285, 100)
    gui.StudsOffset = Vector3.new(0, 3.6, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 85
    gui.Parent = head

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
    frame.BackgroundTransparency = 0.12
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -14, 1, -14)
    label.Position = UDim2.fromOffset(7, 7)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(245, 248, 255)
    label.TextWrapped = true
    label.TextScaled = true
    label.Font = Enum.Font.GothamMedium
    label.Text = "AstraBrain online"
    label.Parent = frame

    return label
end

local function setDebug(agent, key, value)
    agent:SetAttribute(key, value)
end

local function think(state, text)
    if text == state.lastThought then
        return
    end

    state.lastThought = text
    state.thoughtLabel.Text = "💭 " .. text
    setDebug(state.agent, "LastThought", text)

    print(string.format(
        "[AstraBrain][%s][%s][Tick %d] %s",
        state.agent.Name,
        state.role,
        state.tick,
        text
    ))
end

local function remember(state, kind, data, importance)
    state.memory:Remember(state.tick, kind, data, importance)
    local shortCount, longCount = state.memory:Count()
    setDebug(state.agent, "MemoryShortCount", shortCount)
    setDebug(state.agent, "MemoryLongCount", longCount)
end

local function setBelief(state, key, value, confidence, source)
    local belief = state.belief:Set(state.tick, key, value, confidence, source)
    setDebug(state.agent, "Belief_" .. key, tostring(value))
    setDebug(state.agent, "Belief_" .. key .. "_Confidence", math.floor(belief.confidence * 100))
end

local function directMove(state, position, speed)
    state.humanoid.WalkSpeed = speed or Config.WalkSpeed
    state.targetPosition = position
    setDebug(state.agent, "TargetPosition", position)
    state.humanoid:MoveTo(position)
end

local function pathMove(state, position)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
    })

    local ok = pcall(function()
        path:ComputeAsync(state.root.Position, position)
    end)

    if not ok or path.Status ~= Enum.PathStatus.Success then
        directMove(state, position, Config.WalkSpeed)
        return false
    end

    local waypoints = path:GetWaypoints()
    if #waypoints >= 2 then
        local waypoint = waypoints[2]
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            state.humanoid.Jump = true
        end
        directMove(state, waypoint.Position, Config.WalkSpeed)
        return true
    end

    directMove(state, position, Config.WalkSpeed)
    return true
end

local function deterministicExplorePosition(state)
    local seed = 97
    for i = 1, #state.agent.Name do
        seed += string.byte(state.agent.Name, i)
    end

    local angle = math.rad((seed + state.tick * 137) % 360)
    local radius = 12 + ((seed + state.tick * 7) % 20)

    return state.homePosition + Vector3.new(
        math.cos(angle) * radius,
        0,
        math.sin(angle) * radius
    )
end

local function processMessages(state)
    for _, message in ipairs(Communication.ReceiveAll(state.agent)) do
        remember(state, "communication", message, 0.75)

        if message.type == "resource_report" and state.role == Config.Roles.Gatherer then
            state.resourceReport = {
                resourceName = message.payload.resourceName,
                position = message.payload.position,
                from = message.from,
                tick = message.tick,
            }

            setBelief(state, "reported_resource", true, 0.82, message.from)
            think(state, "ได้รับพิกัด Resource จาก " .. message.from)
        end
    end
end

local function updateNeeds(state)
    state.needs.energy = math.max(0, state.needs.energy - Config.EnergyDecayPerTick)
    state.needs.social = math.max(0, state.needs.social - 0.6)

    if state.humanoid.Health < state.humanoid.MaxHealth * 0.45 then
        state.needs.safety = math.max(0, state.needs.safety - 8)
    end

    setDebug(state.agent, "Energy", math.floor(state.needs.energy))
    setDebug(state.agent, "Safety", math.floor(state.needs.safety))
    setDebug(state.agent, "Social", math.floor(state.needs.social))
end

local function updateBeliefsFromObservation(state, observations)
    if #observations.resources > 0 then
        local closest = observations.resources[1]
        setBelief(state, "resource_available", true, 0.96, "direct_observation")
        remember(state, "resource_seen", {
            name = closest.instance.Name,
            position = closest.position,
            distance = closest.distance,
        }, 0.65)

        setDebug(state.agent, "MemoryResourceName", closest.instance.Name)
        setDebug(state.agent, "MemoryResourcePosition", closest.position)
    else
        setBelief(state, "resource_available", false, 0.72, "direct_observation")
    end

    if #observations.threats > 0 then
        setBelief(state, "threat_nearby", true, 0.99, "direct_observation")
        state.needs.safety = math.max(0, state.needs.safety - 15)
    else
        setBelief(state, "threat_nearby", false, 0.8, "direct_observation")
        state.needs.safety = math.min(100, state.needs.safety + 3)
    end

    setBelief(state, "agent_nearby", #observations.agents > 0, 0.85, "direct_observation")
end

local function scoutReport(state, observations)
    if state.role ~= Config.Roles.Scout or #observations.resources == 0 then
        return
    end

    if state.tick - state.lastReportTick < 2 then
        return
    end

    local closest = observations.resources[1]
    local sent = Communication.BroadcastResourceReport(
        state.agent,
        state.folders.agents,
        state.tick,
        closest.instance,
        closest.position,
        Config.CommunicationRange
    )

    if sent > 0 then
        state.lastReportTick = state.tick
        remember(state, "resource_report_sent", {
            resourceName = closest.instance.Name,
            position = closest.position,
            recipients = sent,
        }, 0.8)
        think(state, "พบ " .. closest.instance.Name .. " → ส่งพิกัดให้ Gatherer")
    end
end

local function collectResource(state, resource)
    if state.role ~= Config.Roles.Gatherer then
        return false
    end

    if not resource or not resource.Parent or resource:GetAttribute("Active") == false then
        return false
    end

    if (resource.Position - state.root.Position).Magnitude > Config.CollectDistance then
        return false
    end

    local amount = resource:GetAttribute("Amount") or 1
    resource:SetAttribute("Active", false)
    resource.Transparency = 1
    resource.CanQuery = false

    local teamResources = WorldState.AddResources(amount)

    remember(state, "resource_collected", {
        name = resource.Name,
        amount = amount,
        position = resource.Position,
    }, 0.9)

    state.resourceReport = nil
    setDebug(state.agent, "TeamResources", teamResources)
    think(state, string.format("เก็บ %s → คลังกลาง = %d", resource.Name, teamResources))

    task.delay(Config.ResourceRespawnSeconds, function()
        if resource.Parent then
            resource.Transparency = 0
            resource.CanQuery = true
            resource:SetAttribute("Active", true)
        end
    end)

    return true
end

local function executeGather(state, observations)
    local target = observations.resources[1]

    if target then
        setDebug(state.agent, "TargetName", target.instance.Name)

        if target.distance <= Config.CollectDistance then
            collectResource(state, target.instance)
        else
            think(state, "เห็น " .. target.instance.Name .. " → กำลังไปเก็บ")
            directMove(state, target.position, Config.WalkSpeed)
        end
        return
    end

    if state.resourceReport then
        local report = state.resourceReport
        local actual = state.folders.resources:FindFirstChild(report.resourceName)

        if actual and actual:IsA("BasePart") and actual:GetAttribute("Active") ~= false then
            local distance = (actual.Position - state.root.Position).Magnitude
            if distance <= Config.CollectDistance then
                collectResource(state, actual)
            else
                think(state, "ตามพิกัด Scout → " .. report.resourceName)
                pathMove(state, actual.Position)
            end
            return
        end

        if (report.position - state.root.Position).Magnitude > Config.ArrivalDistance then
            think(state, "กำลังตรวจพิกัดที่ Scout รายงาน")
            pathMove(state, report.position)
            return
        end

        state.resourceReport = nil
    end

    directMove(state, deterministicExplorePosition(state), Config.WalkSpeed)
end

local function executeBuild(state)
    local active = Construction.GetActive()

    if not active then
        local blueprint = Construction.GetNextBlueprint(state.folders, Config)
        if not blueprint then
            think(state, "สิ่งปลูกสร้างหลักครบแล้ว → รอภารกิจใหม่")
            return
        end

        if WorldState.GetResources() < blueprint.cost then
            think(state, string.format("รอ Resource สำหรับ %s (%d/%d)", blueprint.displayName, WorldState.GetResources(), blueprint.cost))
            return
        end

        active = Construction.TryStart(state.agent, state.folders, Config, state.tick)
    end

    if not active then
        return
    end

    local distance = (active.position - state.root.Position).Magnitude
    if distance > Config.ArrivalDistance + 2 then
        think(state, "ไปยังจุดก่อสร้าง " .. active.blueprint.displayName)
        pathMove(state, active.position)
        return
    end

    local ok, status, detail = Construction.Step(state.agent, state.folders, Config, state.tick)

    if ok and status == "progress" then
        think(state, string.format("กำลังก่อสร้าง %s → %d%%", active.blueprint.displayName, detail))
    elseif ok and status == "completed" then
        remember(state, "structure_built", {
            blueprint = active.blueprint.id,
            position = active.position,
        }, 1.0)
        think(state, "สร้าง " .. active.blueprint.displayName .. " สำเร็จ")
    elseif status == "too_far" and typeof(detail) == "Vector3" then
        pathMove(state, detail)
    end
end

local function executeFlee(state, observations)
    local threat = observations.threats[1]
    if not threat then
        return
    end

    local away = state.root.Position - threat.position
    if away.Magnitude < 0.1 then
        away = Vector3.new(1, 0, 0)
    end

    think(state, "พบภัยคุกคาม → ถอยออกจากพื้นที่")
    directMove(state, state.root.Position + away.Unit * 24, Config.RunSpeed)
end

local function executeRest(state)
    state.humanoid:MoveTo(state.root.Position)
    state.needs.energy = math.min(100, state.needs.energy + Config.EnergyRestGain)
    think(state, "พักฟื้นพลังงาน")
end

local function executeExplore(state)
    think(state, "สำรวจพื้นที่และอัปเดต World Model")
    directMove(state, deterministicExplorePosition(state), Config.WalkSpeed)
end

local function executeGoal(state, goal, observations)
    if goal == "Flee" then
        executeFlee(state, observations)
    elseif goal == "Rest" then
        executeRest(state)
    elseif goal == "GatherResource" then
        executeGather(state, observations)
    elseif goal == "BuildStructure" then
        executeBuild(state)
    elseif goal == "Communicate" then
        if state.role == Config.Roles.Scout then
            scoutReport(state, observations)
        elseif state.role == Config.Roles.Builder then
            think(state, "รอ Resource จาก Gatherer เพื่อก่อสร้าง")
        else
            executeExplore(state)
        end
    else
        executeExplore(state)
    end
end

local function updateStuck(state)
    local moved = (state.root.Position - state.lastPosition).Magnitude

    if state.targetPosition and (state.targetPosition - state.root.Position).Magnitude > Config.ArrivalDistance then
        if moved <= Config.StuckDistanceEpsilon then
            state.stuckTicks += 1
        else
            state.stuckTicks = 0
        end
    else
        state.stuckTicks = 0
    end

    state.lastPosition = state.root.Position
    setDebug(state.agent, "StuckTicks", state.stuckTicks)

    if state.stuckTicks >= Config.StuckTicksBeforePath and state.targetPosition then
        think(state, "เส้นทางติดขัด → Pathfinding ใหม่")
        pathMove(state, state.targetPosition)
        state.stuckTicks = 0
    end
end

function Brain.Start(agent)
    if runningAgents[agent] then
        return runningAgents[agent]
    end

    local humanoid = agent:FindFirstChildOfClass("Humanoid")
    local root = agent:FindFirstChild("HumanoidRootPart")
    local head = agent:FindFirstChild("Head")

    if not humanoid or not root or not head then
        warn("[AstraBrain] Invalid agent model:", agent:GetFullName())
        return nil
    end

    local folders = WorldState.Ensure()
    local role = inferRole(agent)
    agent:SetAttribute("Role", role)
    agent:SetAttribute("IsAstraAgent", true)
    agent:SetAttribute("AgentID", agent.Name)

    humanoid.WalkSpeed = Config.WalkSpeed
    humanoid.AutoRotate = true
    humanoid.DisplayName = agent.Name

    for _, obj in ipairs(agent:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.Anchored = false
        end
    end

    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    local state = {
        agent = agent,
        humanoid = humanoid,
        root = root,
        head = head,
        folders = folders,
        config = Config,
        role = role,
        tick = 0,
        homePosition = root.Position,
        lastPosition = root.Position,
        targetPosition = nil,
        stuckTicks = 0,
        lastThought = "",
        lastReportTick = -999,
        resourceReport = nil,
        memory = Memory.new(Config),
        belief = Belief.new(Config),
        thoughtLabel = createThoughtBubble(agent, head),
        needs = {
            energy = Config.EnergyStart,
            safety = Config.SafetyStart,
            social = Config.SocialStart,
        },
    }

    runningAgents[agent] = state

    setDebug(agent, "State", "Booting")
    setDebug(agent, "Goal", "None")
    setDebug(agent, "Plan", "None")
    setDebug(agent, "Energy", state.needs.energy)
    setDebug(agent, "Safety", state.needs.safety)
    setDebug(agent, "Social", state.needs.social)

    think(state, "AstraBrain Online — Role: " .. role)

    task.spawn(function()
        while agent.Parent and humanoid.Health > 0 do
            task.wait(Config.TickSeconds)

            state.tick += 1
            setDebug(agent, "Tick", state.tick)

            updateNeeds(state)
            processMessages(state)

            setDebug(agent, "State", "Observing")
            local observations = Perception.Observe(agent, folders, Config)
            updateBeliefsFromObservation(state, observations)
            state.belief:Decay(state.tick)

            scoutReport(state, observations)

            local nextBlueprint = Construction.GetNextBlueprint(folders, Config)
            local activeBuild = Construction.GetActive()
            local constructionAvailable = activeBuild ~= nil
                or (nextBlueprint ~= nil and WorldState.GetResources() >= nextBlueprint.cost)

            local goal, score = Planner.ChooseGoal(
                role,
                observations,
                state,
                WorldState.GetResources(),
                constructionAvailable
            )

            local plan = Planner.MakePlan(goal)
            local planText = table.concat(plan, " > ")

            setDebug(agent, "Goal", goal)
            setDebug(agent, "GoalScore", math.floor(score))
            setDebug(agent, "Plan", planText)
            setDebug(agent, "State", "Acting")

            remember(state, "decision", {
                goal = goal,
                plan = planText,
            }, 0.5)

            executeGoal(state, goal, observations)
            updateStuck(state)
        end

        runningAgents[agent] = nil
    end)

    return state
end

return Brain

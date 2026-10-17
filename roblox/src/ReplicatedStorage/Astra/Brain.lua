local PathfindingService = game:GetService("PathfindingService")

local Config = require(script.Parent.Config)
local WorldState = require(script.Parent.WorldState)
local Memory = require(script.Parent.Memory)
local Belief = require(script.Parent.Belief)
local Communication = require(script.Parent.Communication)
local Perception = require(script.Parent.Perception)
local SharedKnowledge = require(script.Parent.SharedKnowledge)
local Inventory = require(script.Parent.Inventory)
local ResourceEconomy = require(script.Parent.ResourceEconomy)
local Storage = require(script.Parent.Storage)
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

local function createThoughtBubble(head)
    local old = head:FindFirstChild("AstraThought")
    if old then
        old:Destroy()
    end

    local gui = Instance.new("BillboardGui")
    gui.Name = "AstraThought"
    gui.Size = UDim2.fromOffset(300, 105)
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

local function debug(agent, key, value)
    agent:SetAttribute(key, value)
end

local function think(state, text)
    if state.lastThought == text then
        return
    end
    state.lastThought = text
    state.thoughtLabel.Text = "💭 " .. text
    debug(state.agent, "LastThought", text)
    print(string.format("[AstraBrain][%s][%s][Tick %d] %s", state.agent.Name, state.role, state.tick, text))
end

local function remember(state, kind, data, importance)
    state.memory:Remember(state.tick, kind, data, importance)
    local shortCount, longCount = state.memory:Count()
    debug(state.agent, "MemoryShortCount", shortCount)
    debug(state.agent, "MemoryLongCount", longCount)
end

local function setBelief(state, key, value, confidence, source, provenance, expiresTick)
    local belief = state.belief:Set(state.tick, key, value, confidence, source, provenance, expiresTick)
    debug(state.agent, "LastBeliefUpdate", key)
    debug(state.agent, "LastBeliefSource", source or "unknown")
    debug(state.agent, "KnowledgeTargetConfidence", math.floor((belief.confidence or 0) * 100))
    return belief
end

local function updateInventoryDebug(state)
    debug(state.agent, "CarryTotal", state.inventory:GetTotal())
    debug(state.agent, "CarryCapacity", state.inventory.capacity)
    for resourceType, _ in pairs(Config.ResourceTypes) do
        debug(state.agent, "Carry_" .. resourceType, state.inventory:Get(resourceType))
    end
end

local function directMove(state, position, speed)
    state.humanoid.WalkSpeed = speed or Config.WalkSpeed
    state.targetPosition = position
    debug(state.agent, "TargetPosition", position)
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
    return state.homePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function invalidateReport(state, reason, broadcast)
    local report = state.resourceReport
    if not report then
        return
    end

    state.belief:Invalidate("resource:" .. report.resourceId, state.tick, reason)
    SharedKnowledge.InvalidateByResource(report.resourceId, state.tick, state.agent.Name)

    if broadcast then
        Communication.BroadcastStatus(state.agent, state.folders.agents, state.tick, "resource_missing", {
            observationId = report.observationId,
            resourceId = report.resourceId,
            resourceType = report.resourceType,
            position = report.position,
            reason = reason,
            provenance = "direct",
        }, Config)
    end

    state.resourceReport = nil
    debug(state.agent, "CurrentKnowledgeTarget", "None")
    debug(state.agent, "KnowledgeTargetConfidence", 0)
end

local function processMessages(state)
    local messages, expired = Communication.ReceiveAll(state.agent, state.tick)
    debug(state.agent, "CommunicationInboxSize", #messages)

    if expired > 0 then
        state.expiredMessages += expired
        debug(state.agent, "ExpiredBeliefs", state.expiredMessages)
    end

    for _, message in ipairs(messages) do
        if state.processedMessages[message.messageId] then
            state.duplicateMessages += 1
            debug(state.agent, "DuplicateMessagesDropped", state.duplicateMessages)
            continue
        end
        state.processedMessages[message.messageId] = true
        debug(state.agent, "LastMessageReceived", message.messageId)

        if message.type == "resource_report" and state.role == Config.Roles.Gatherer then
            local payload = message.payload
            if not state.processedObservations[payload.observationId] then
                state.processedObservations[payload.observationId] = true

                local expiresTick = state.tick + Config.SharedKnowledgeTTL
                state.resourceReport = {
                    observationId = payload.observationId,
                    resourceId = payload.resourceId,
                    resourceType = payload.resourceType,
                    position = payload.position,
                    from = message.from,
                    confidence = Config.ReportedResourceConfidence,
                    receivedTick = state.tick,
                    expiresTick = expiresTick,
                }

                remember(state, "resource_report_received", {
                    sourceType = "communication",
                    sourceAgentId = message.from,
                    originalObservationId = payload.observationId,
                    resourceId = payload.resourceId,
                    resourceType = payload.resourceType,
                    position = payload.position,
                    receivedTick = state.tick,
                }, 0.85)

                setBelief(state, "resource:" .. payload.resourceId, {
                    resourceType = payload.resourceType,
                    position = payload.position,
                }, Config.ReportedResourceConfidence, message.from, "communication", expiresTick)

                debug(state.agent, "CurrentKnowledgeTarget", payload.resourceId)
                state.folders.state:SetAttribute("P1_GathererReceived", true)
                state.folders.state:SetAttribute("P1_Belief75", true)
                think(state, string.format("%s รายงาน %s → เชื่อ %d%%", message.from, payload.resourceType, math.floor(Config.ReportedResourceConfidence * 100)))
            else
                state.duplicateMessages += 1
                debug(state.agent, "DuplicateMessagesDropped", state.duplicateMessages)
            end
        elseif message.type == "resource_missing" then
            local payload = message.payload
            local belief = state.belief:Get("resource:" .. tostring(payload.resourceId), state.tick)
            if belief then
                state.belief:Invalidate("resource:" .. payload.resourceId, state.tick, "peer_missing")
            end
            if state.resourceReport and state.resourceReport.resourceId == payload.resourceId then
                state.resourceReport = nil
            end
        end
    end
end

local function updateNeeds(state)
    state.needs.energy = math.max(0, state.needs.energy - Config.EnergyDecayPerTick)
    state.needs.social = math.max(0, state.needs.social - 0.6)
    if state.humanoid.Health < state.humanoid.MaxHealth * 0.45 then
        state.needs.safety = math.max(0, state.needs.safety - 8)
    end
    debug(state.agent, "Energy", math.floor(state.needs.energy))
    debug(state.agent, "Safety", math.floor(state.needs.safety))
    debug(state.agent, "Social", math.floor(state.needs.social))
end

local function updateBeliefsFromObservation(state, observations)
    for _, observation in ipairs(observations.resources) do
        setBelief(state, "resource:" .. observation.resourceId, {
            resourceType = observation.subtype,
            position = observation.position,
        }, Config.DirectObservationConfidence, state.agent.Name, "direct", state.tick + Config.SharedKnowledgeTTL)

        remember(state, "resource_seen", {
            sourceType = "direct",
            resourceId = observation.resourceId,
            resourceType = observation.subtype,
            position = observation.position,
            distance = observation.distance,
            observationId = observation.id,
        }, 0.65)

        debug(state.agent, "LastObservationId", observation.id)

        if state.resourceReport and state.resourceReport.resourceId == observation.resourceId then
            state.folders.state:SetAttribute("P1_Verified100", true)
            debug(state.agent, "KnowledgeTargetConfidence", 100)
            Communication.BroadcastStatus(state.agent, state.folders.agents, state.tick, "resource_verified", {
                observationId = observation.id,
                resourceId = observation.resourceId,
                resourceType = observation.subtype,
                position = observation.position,
                confidence = 1.0,
                provenance = "direct",
            }, Config)
            state.resourceReport = nil
            think(state, observation.subtype .. " ยืนยันด้วยตาตัวเอง → Confidence 100%")
        end
    end

    if #observations.threats > 0 then
        setBelief(state, "threat_nearby", true, 0.99, state.agent.Name, "direct", state.tick + 4)
        state.needs.safety = math.max(0, state.needs.safety - 15)
    else
        setBelief(state, "threat_nearby", false, 0.8, state.agent.Name, "direct", state.tick + 4)
        state.needs.safety = math.min(100, state.needs.safety + 3)
    end
end

local function scoutReport(state, observations)
    if state.role ~= Config.Roles.Scout or #observations.resources == 0 then
        return
    end

    local observation = observations.resources[1]
    local lastTick = state.lastReportedResource[observation.resourceId] or -999
    if state.tick - lastTick < 3 then
        return
    end

    SharedKnowledge.Publish(observation, state.tick, Config.SharedKnowledgeTTL)
    local sent = Communication.BroadcastResourceObservation(state.agent, state.folders.agents, state.tick, observation, Config)

    if sent > 0 then
        state.lastReportedResource[observation.resourceId] = state.tick
        remember(state, "resource_report_sent", {
            observationId = observation.id,
            resourceId = observation.resourceId,
            resourceType = observation.subtype,
            position = observation.position,
            recipients = sent,
        }, 0.8)
        state.folders.state:SetAttribute("P1_ScoutObserved", true)
        state.folders.state:SetAttribute("P1_ScoutSent", true)
        debug(state.agent, "LastMessageSent", observation.id)
        think(state, "พบ " .. observation.subtype .. " → ส่งข่าวให้ Colony")
    end
end

local function collectResource(state, observation)
    if state.role ~= Config.Roles.Gatherer then
        state.folders.state:SetAttribute("P1_RoleGuards", true)
        return false
    end

    local resource = observation and observation.instance
    if not resource or not resource.Parent or resource:GetAttribute("Active") == false then
        return false
    end
    if observation.distance > Config.CollectDistance then
        return false
    end
    if state.inventory:IsFull() then
        return false
    end

    local resourceType = resource:GetAttribute("ResourceType") or observation.subtype or "Wood"
    local amount = resource:GetAttribute("Amount") or 1
    local accepted = state.inventory:Add(resourceType, amount)
    if accepted <= 0 then
        return false
    end

    resource:SetAttribute("Active", false)
    resource.Transparency = 1
    resource.CanQuery = false

    updateInventoryDebug(state)
    state.folders.state:SetAttribute("P1_Collected", true)
    state.folders.state:SetAttribute("P2_CarryObserved", true)
    state.folders.state:SetAttribute("P2_LastCarriedType", resourceType)

    remember(state, "resource_carried", {
        sourceType = "self_action",
        resourceId = resource.Name,
        resourceType = resourceType,
        amount = accepted,
        position = resource.Position,
    }, 0.9)

    SharedKnowledge.InvalidateByResource(resource.Name, state.tick, state.agent.Name)
    state.belief:Invalidate("resource:" .. resource.Name, state.tick, "collected")
    Communication.BroadcastStatus(state.agent, state.folders.agents, state.tick, "resource_missing", {
        observationId = observation.id,
        resourceId = resource.Name,
        resourceType = resourceType,
        position = resource.Position,
        reason = "collected",
        provenance = "self_action",
    }, Config)

    if state.resourceReport and state.resourceReport.resourceId == resource.Name then
        state.resourceReport = nil
    end

    think(state, string.format("เก็บ %s เข้ากระเป๋า %d/%d", resourceType, state.inventory:GetTotal(), state.inventory.capacity))

    task.delay(Config.ResourceRespawnSeconds, function()
        if resource.Parent then
            resource.Transparency = 0
            resource.CanQuery = true
            resource:SetAttribute("Active", true)
        end
    end)

    return true
end

local function depositResources(state)
    if state.role ~= Config.Roles.Gatherer or state.inventory:GetTotal() <= 0 then
        return false
    end

    local depositPosition = Storage.GetDepositPosition(state.storage)
    local distance = (depositPosition - state.root.Position).Magnitude
    if distance > Config.DepositDistance then
        think(state, string.format("ขนของ %d/%d กลับคลัง", state.inventory:GetTotal(), state.inventory.capacity))
        pathMove(state, depositPosition)
        return false
    end

    local snapshot = state.inventory:Drain()
    local depositedTotal = 0
    local summary = {}

    for resourceType, amount in pairs(snapshot) do
        local accepted = ResourceEconomy.Deposit(state.folders.state, resourceType, amount)
        local remainder = amount - accepted
        if remainder > 0 then
            state.inventory:Add(resourceType, remainder)
        end
        if accepted > 0 then
            depositedTotal += accepted
            table.insert(summary, resourceType .. "+" .. tostring(accepted))
            state.folders.state:SetAttribute("P2_Deposited_" .. resourceType, true)
        end
    end

    updateInventoryDebug(state)

    if depositedTotal > 0 then
        table.sort(summary)
        state.folders.state:SetAttribute("P2_DepositObserved", true)
        state.folders.state:SetAttribute("P2_LastDeposit", table.concat(summary, ","))
        remember(state, "resource_deposited", {
            sourceType = "self_action",
            items = snapshot,
            deposited = depositedTotal,
        }, 0.9)
        think(state, "ฝากเข้าคลัง: " .. table.concat(summary, " "))
        return true
    end

    think(state, "คลังเต็ม → ยังถือของไว้")
    return false
end

local function executeGather(state, observations)
    local target = observations.resources[1]
    if target then
        if target.distance <= Config.CollectDistance then
            collectResource(state, target)
        else
            think(state, "เห็น " .. target.subtype .. " → กำลังไปเก็บ")
            directMove(state, target.position, Config.WalkSpeed)
        end
        return
    end

    local report = state.resourceReport
    if report then
        if state.tick > report.expiresTick then
            state.expiredMessages += 1
            debug(state.agent, "ExpiredBeliefs", state.expiredMessages)
            invalidateReport(state, "expired", false)
            think(state, "ข่าว Resource หมดอายุ → ยกเลิกเป้าหมาย")
            return
        end

        local distance = (report.position - state.root.Position).Magnitude
        if distance > Config.ArrivalDistance then
            state.folders.state:SetAttribute("P1_RemoteGoal", true)
            think(state, "ตามพิกัดข่าว → " .. report.resourceType)
            pathMove(state, report.position)
            return
        end

        -- Critical P1 rule: at reported position with no direct Perception result,
        -- treat the report as disproven. Do not inspect Workspace for world truth.
        state.folders.state:SetAttribute("P1_MissingRecovered", true)
        think(state, "ถึงพิกัดแล้วไม่พบ Resource → ยกเลิก Belief")
        invalidateReport(state, "not_found_on_arrival", true)
        return
    end

    executeExplore(state)
end

function executeExplore(state)
    think(state, "สำรวจพื้นที่")
    directMove(state, deterministicExplorePosition(state), Config.WalkSpeed)
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
    think(state, "พบภัยคุกคาม → ถอย")
    directMove(state, state.root.Position + away.Unit * 24, Config.RunSpeed)
end

local function executeRest(state)
    state.humanoid:MoveTo(state.root.Position)
    state.needs.energy = math.min(100, state.needs.energy + Config.EnergyRestGain)
    think(state, "พักฟื้นพลังงาน")
end

local function executeBuild(state)
    if state.role ~= Config.Roles.Builder then
        return
    end

    local active = Construction.GetActive()
    if not active then
        local blueprint = Construction.GetNextBlueprint(state.folders, Config)
        if not blueprint then
            think(state, "สิ่งปลูกสร้างหลักครบแล้ว")
            return
        end

        if not ResourceEconomy.CanAfford(state.folders.state, blueprint.recipe) then
            think(state, "รอวัตถุดิบสำหรับ " .. blueprint.displayName)
            return
        end

        active = Construction.TryStart(state.agent, state.folders, Config, state.tick)
    end

    if not active then
        return
    end

    local distance = (active.position - state.root.Position).Magnitude
    if distance > Config.ArrivalDistance + 2 then
        think(state, "ไปจุดก่อสร้าง " .. active.blueprint.displayName)
        pathMove(state, active.position)
        return
    end

    local ok, status, detail = Construction.Step(state.agent, state.folders, Config, state.tick)
    if ok and status == "progress" then
        think(state, string.format("สร้าง %s → %d%%", active.blueprint.displayName, detail))
    elseif ok and status == "completed" then
        remember(state, "structure_built", {
            sourceType = "self_action",
            blueprint = active.blueprint.id,
            position = active.position,
        }, 1.0)
        think(state, "สร้าง " .. active.blueprint.displayName .. " สำเร็จ")
    elseif status == "too_far" and typeof(detail) == "Vector3" then
        pathMove(state, detail)
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
    debug(state.agent, "StuckTicks", state.stuckTicks)

    if state.stuckTicks >= Config.StuckTicksBeforePath and state.targetPosition then
        think(state, "เส้นทางติด → คำนวณใหม่")
        pathMove(state, state.targetPosition)
        state.stuckTicks = 0
    end
end

local function executeGoal(state, goal, observations)
    debug(state.agent, "Goal", goal)

    if goal == "Flee" then
        executeFlee(state, observations)
    elseif goal == "Rest" then
        executeRest(state)
    elseif goal == "GatherResource" then
        executeGather(state, observations)
    elseif goal == "DepositResources" then
        depositResources(state)
    elseif goal == "BuildStructure" then
        executeBuild(state)
    elseif goal == "Communicate" then
        if state.role == Config.Roles.Scout then
            scoutReport(state, observations)
        elseif state.role == Config.Roles.Builder then
            think(state, "รอวัตถุดิบจาก Gatherer")
        else
            executeExplore(state)
        end
    else
        executeExplore(state)
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
        return nil
    end

    local folders = WorldState.Ensure(Config)
    ResourceEconomy.Ensure(folders.state, Config.StorageCapacity)
    local role = inferRole(agent)
    agent:SetAttribute("Role", role)
    agent:SetAttribute("IsAstraAgent", true)
    humanoid.DisplayName = agent.Name
    humanoid.WalkSpeed = Config.WalkSpeed

    for _, obj in ipairs(agent:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.Anchored = false
        end
    end

    local canSetOwner = root:CanSetNetworkOwnership()
    if canSetOwner then
        root:SetNetworkOwner(nil)
    end

    local state = {
        agent = agent,
        humanoid = humanoid,
        root = root,
        head = head,
        role = role,
        folders = folders,
        storage = Storage.FindOrCreate(folders, Config),
        memory = Memory.new(Config),
        belief = Belief.new(Config),
        inventory = Inventory.new(Config.CarryCapacity),
        thoughtLabel = createThoughtBubble(head),
        homePosition = root.Position,
        targetPosition = nil,
        lastPosition = root.Position,
        stuckTicks = 0,
        tick = WorldState.GetTick(Config),
        localDecisionTick = 0,
        lastThought = "",
        resourceReport = nil,
        processedMessages = {},
        processedObservations = {},
        duplicateMessages = 0,
        expiredMessages = 0,
        lastReportedResource = {},
        needs = {
            energy = Config.EnergyStart,
            safety = Config.SafetyStart,
            social = Config.SocialStart,
        },
    }

    runningAgents[agent] = state

    debug(agent, "State", "Online")
    debug(agent, "RuntimeVersion", Config.RuntimeVersion)
    debug(agent, "DuplicateMessagesDropped", 0)
    debug(agent, "ExpiredBeliefs", 0)
    updateInventoryDebug(state)

    if role ~= Config.Roles.Gatherer then
        folders.state:SetAttribute("P1_RoleGuards", true)
    end

    think(state, "AstraBrain P2 online")

    humanoid.Died:Connect(function()
        runningAgents[agent] = nil
    end)

    task.spawn(function()
        while runningAgents[agent] == state and agent.Parent and humanoid.Health > 0 do
            task.wait(Config.TickSeconds)

            state.tick = WorldState.GetTick(Config)
            state.localDecisionTick += 1
            debug(agent, "Tick", state.tick)
            debug(agent, "LocalDecisionTick", state.localDecisionTick)

            if state.resourceReport and state.tick > state.resourceReport.expiresTick then
                state.expiredMessages += 1
                debug(agent, "ExpiredBeliefs", state.expiredMessages)
                invalidateReport(state, "expired", false)
            end

            processMessages(state)
            updateNeeds(state)

            local observations = Perception.Observe(agent, folders, Config, state.tick)
            updateBeliefsFromObservation(state, observations)
            state.expiredMessages += state.belief:Decay(state.tick)
            debug(agent, "ExpiredBeliefs", state.expiredMessages)

            if role == Config.Roles.Scout then
                scoutReport(state, observations)
            end

            debug(agent, "KnownResourceCount", SharedKnowledge.ActiveCount(state.tick))

            local goal, score = Planner.ChooseGoal(state, observations, Construction, ResourceEconomy, Config)
            debug(agent, "GoalScore", score)
            debug(agent, "Plan", goal)
            executeGoal(state, goal, observations)
            updateStuck(state)
        end
    end)

    return state
end

return Brain

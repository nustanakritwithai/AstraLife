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
local Needs = require(script.Parent.Needs)
local InventoryShadow = require(script.Parent.SurvivalCrafting.Adapter.InventoryShadow)
local ProfessionAdapter = require(script.Parent.SurvivalCrafting.Adapter.ProfessionAdapter)
local P7OutcomeSink = require(script.Parent.SurvivalCrafting.Adapter.P7OutcomeSink)

local BrainIntegrated = {}
local runningAgents = setmetatable({}, { __mode = "k" })

local function inferRole(agent)
    local role = agent:GetAttribute("Role")
    if role and role ~= "" and role ~= "Unassigned" then return role end
    local name = string.lower(agent.Name)
    if string.find(name, "scout", 1, true) then return Config.Roles.Scout end
    if string.find(name, "gather", 1, true) then return Config.Roles.Gatherer end
    if string.find(name, "builder", 1, true) then return Config.Roles.Builder end
    return Config.Roles.Explorer
end

local function createThoughtBubble(head)
    local old = head:FindFirstChild("AstraThought")
    if old then old:Destroy() end
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
    if state.lastThought == text then return end
    state.lastThought = text
    state.thoughtLabel.Text = "💭 " .. text
    debug(state.agent, "LastThought", text)
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
    local actorId = state.agent.Name
    for resourceType in pairs(Config.ResourceTypes) do
        debug(state.agent, "Carry_" .. resourceType, state.inventory:Get(resourceType))
        debug(state.agent, "CarryWorld_" .. resourceType, state.worldCarried[resourceType] or 0)
        -- I3: S4-backed LivingWorld projection cap (Carry must not exceed for LW units).
        debug(state.agent, "CarryS4_" .. resourceType, InventoryShadow.ProjectedAmount(actorId, resourceType))
    end
end

local function directMove(state, position, speed)
    state.humanoid.WalkSpeed = speed or Config.WalkSpeed
    state.targetPosition = position
    debug(state.agent, "TargetPosition", position)
    state.humanoid:MoveTo(position)
end

local function samePathTarget(state, position)
    return state.lastPathTarget
        and (state.lastPathTarget - position).Magnitude <= (Config.PathTargetChangeDistance or 4)
end

local function followCachedPath(state)
    local waypoints = state.cachedWaypoints
    local index = state.cachedWaypointIndex or 2
    if not waypoints or #waypoints < index then return false end

    while index <= #waypoints and (waypoints[index].Position - state.root.Position).Magnitude <= 3 do
        index += 1
    end
    state.cachedWaypointIndex = index

    local waypoint = waypoints[index]
    if not waypoint then return false end
    if waypoint.Action == Enum.PathWaypointAction.Jump then state.humanoid.Jump = true end
    directMove(state, waypoint.Position, Config.WalkSpeed)
    state.pathCacheHits += 1
    debug(state.agent, "PathCacheHits", state.pathCacheHits)
    return true
end

local function pathMove(state, position, force)
    local interval = Config.PathRecomputeIntervalTicks or 2
    if not force
        and samePathTarget(state, position)
        and state.lastPathComputeTick
        and state.tick - state.lastPathComputeTick < interval
        and followCachedPath(state)
    then
        return true
    end

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
    })
    local ok = pcall(function() path:ComputeAsync(state.root.Position, position) end)

    state.pathComputeCount += 1
    state.lastPathComputeTick = state.tick
    state.lastPathTarget = position
    debug(state.agent, "PathComputeCount", state.pathComputeCount)

    if not ok or path.Status ~= Enum.PathStatus.Success then
        state.cachedWaypoints = nil
        state.cachedWaypointIndex = nil
        directMove(state, position, Config.WalkSpeed)
        return false
    end

    state.cachedWaypoints = path:GetWaypoints()
    state.cachedWaypointIndex = 2
    if followCachedPath(state) then return true end
    directMove(state, position, Config.WalkSpeed)
    return true
end

local function cleanupExpiringMap(map, tick)
    for key, expiresTick in pairs(map) do
        if type(expiresTick) == "number" and tick > expiresTick then map[key] = nil end
    end
end

local function nextI3Tx(state, kind, resourceType)
    state.i3TxSeq = (state.i3TxSeq or 0) + 1
    return string.format(
        "i3:%s:%s:%s:%d:%d",
        kind,
        state.agent.Name,
        tostring(resourceType),
        state.tick,
        state.i3TxSeq
    )
end


local function i6Api()
    local parent = game:GetService("ServerScriptService"):FindFirstChild("AstraSurvivalCrafting")
    return parent and parent:FindFirstChild("I6ProfessionApi")
end

-- Wait/queue until I6ProfessionApi exists (bounded). Never silent-drop outcomes before API boots.
local I6_OUTCOME_WAIT_SECONDS = 45
local function i6NotifyOutcome(payload)
    if type(payload) ~= "table" then
        return
    end
    task.spawn(function()
        local api = i6Api()
        if not api then
            local sss = game:GetService("ServerScriptService")
            local parent = sss:FindFirstChild("AstraSurvivalCrafting")
                or sss:WaitForChild("AstraSurvivalCrafting", I6_OUTCOME_WAIT_SECONDS)
            if parent then
                api = parent:FindFirstChild("I6ProfessionApi")
                    or parent:WaitForChild("I6ProfessionApi", I6_OUTCOME_WAIT_SECONDS)
            end
        end
        if not api then
            return
        end
        pcall(function()
            api:Invoke("IngestOutcome", payload)
        end)
    end)
end

local function i6HarvestOpts(state, resourceType)
    local ctx = ProfessionAdapter.HarvestContext(resourceType, state.agent.Name)
    if not ctx then
        return nil
    end
    debug(state.agent, "I6GatherSourceKind", ctx.sourceKind or "None")
    debug(state.agent, "I6GatherToolClass", ctx.toolClass or "None")
    debug(state.agent, "I6GatherToolTier", ctx.toolTier or 0)
    state.folders.state:SetAttribute("I6_GatherQuoteObserved", true)
    return {
        sourceKind = ctx.sourceKind,
        context = ctx.context,
        toolClass = ctx.toolClass,
        toolTier = ctx.toolTier,
    }
end

local function addWorldProvenance(state, resourceType, amount)
    state.worldCarried[resourceType] = (state.worldCarried[resourceType] or 0) + math.max(0, amount or 0)
end

local function consumeWorldProvenance(state, resourceType, amount)
    local current = state.worldCarried[resourceType] or 0
    local consumed = math.min(current, math.max(0, amount or 0))
    state.worldCarried[resourceType] = current - consumed
    return consumed
end

local function w6TransactionId(state, action, resourceType)
    return string.format(
        "w6:%s:%s:%s:%d",
        tostring(action),
        state.agent.Name,
        tostring(resourceType or "none"),
        state.localDecisionTick
    )
end

local function w6Navigate(state, resourceType, message)
    local bridge = state.worldBridge
    if not bridge then return false, { ok = false, reason = "bridge_unavailable" } end

    local nav = bridge.Navigate(state.agent.Name, state.root.Position, resourceType, 14)
    if nav.ok and nav.atSource then return true, nav end
    if nav.ok and nav.nextPosition then
        state.folders.state:SetAttribute("W6_AgentNavigationObserved", true)
        debug(state.agent, "W6WorldTarget", resourceType)
        think(state, message)
        -- W5 chooses the safe logical route; Roblox pathfinding executes the
        -- next logical waypoint against real geometry.
        pathMove(state, nav.nextPosition)
        return false, nav
    end
    debug(state.agent, "W6WorldTargetReason", nav.reason or "no_source")
    return false, nav
end

local function deterministicExplorePosition(state)
    local seed = 97
    for i = 1, #state.agent.Name do seed += string.byte(state.agent.Name, i) end
    local angle = math.rad((seed + state.tick * 137) % 360)
    local radius = 12 + ((seed + state.tick * 7) % 20)
    return state.homePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function removeReport(state, report)
    if not report then return end
    if state.resourceReports[report.resourceType] == report then state.resourceReports[report.resourceType] = nil end
    if state.resourceReport == report then state.resourceReport = nil end
end

local function invalidateReport(state, report, reason, broadcast)
    if not report then return end
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
    removeReport(state, report)
    debug(state.agent, "CurrentKnowledgeTarget", "None")
    debug(state.agent, "KnowledgeTargetConfidence", 0)
end

local function processMessages(state)
    local messages, expired = Communication.ReceiveAll(state.agent, state.tick, Config)
    debug(state.agent, "CommunicationInboxSize", #messages)
    state.expiredMessages += expired or 0

    for _, message in ipairs(messages) do
        local messageUntil = state.processedMessages[message.messageId]
        if messageUntil and messageUntil >= state.tick then
            state.duplicateMessages += 1
            continue
        end
        state.processedMessages[message.messageId] = state.tick + Config.MessageTTL * 2
        debug(state.agent, "LastMessageReceived", message.messageId)

        if message.type == "resource_report" and state.role == Config.Roles.Gatherer then
            local payload = message.payload
            local observationUntil = state.processedObservations[payload.observationId]
            if not observationUntil or observationUntil < state.tick then
                state.processedObservations[payload.observationId] = state.tick + Config.SharedKnowledgeTTL * 2
                local expiresTick = state.tick + Config.SharedKnowledgeTTL
                local report = {
                    observationId = payload.observationId,
                    resourceId = payload.resourceId,
                    resourceType = payload.resourceType,
                    position = payload.position,
                    from = message.from,
                    confidence = Config.ReportedResourceConfidence,
                    receivedTick = state.tick,
                    expiresTick = expiresTick,
                }
                state.resourceReport = report
                state.resourceReports[payload.resourceType] = report
                remember(state, "resource_report_received", {
                    sourceType = "communication",
                    sourceAgentId = message.from,
                    originalObservationId = payload.observationId,
                    resourceId = payload.resourceId,
                    resourceType = payload.resourceType,
                    position = payload.position,
                    receivedTick = state.tick,
                }, 0.85)
                setBelief(
                    state,
                    "resource:" .. payload.resourceId,
                    { resourceType = payload.resourceType, position = payload.position },
                    Config.ReportedResourceConfidence,
                    message.from,
                    "communication",
                    expiresTick
                )
                debug(state.agent, "CurrentKnowledgeTarget", payload.resourceId)
                state.folders.state:SetAttribute("P1_GathererReceived", true)
                state.folders.state:SetAttribute("P1_Belief75", true)
                think(state, string.format("%s รายงาน %s → เชื่อ %d%%", message.from, payload.resourceType, math.floor(Config.ReportedResourceConfidence * 100)))
            else
                state.duplicateMessages += 1
            end
        elseif message.type == "resource_missing" then
            local payload = message.payload
            state.belief:Invalidate("resource:" .. tostring(payload.resourceId), state.tick, "peer_missing")
            for _, report in pairs(state.resourceReports) do
                if report.resourceId == payload.resourceId then removeReport(state, report) break end
            end
        end
    end

    debug(state.agent, "DuplicateMessagesDropped", state.duplicateMessages)
    debug(state.agent, "ExpiredBeliefs", state.expiredMessages)
end

local function updateBeliefsFromObservation(state, observations)
    for _, observation in ipairs(observations.resources) do
        setBelief(
            state,
            "resource:" .. observation.resourceId,
            { resourceType = observation.subtype, position = observation.position },
            Config.DirectObservationConfidence,
            state.agent.Name,
            "direct",
            state.tick + Config.SharedKnowledgeTTL
        )
        remember(state, "resource_seen", {
            sourceType = "direct",
            resourceId = observation.resourceId,
            resourceType = observation.subtype,
            position = observation.position,
            distance = observation.distance,
            observationId = observation.id,
        }, 0.65)
        debug(state.agent, "LastObservationId", observation.id)

        if not state.discoveredResources[observation.resourceId] then
            state.discoveredResources[observation.resourceId] = true
            state.discoveryCount += 1
            debug(state.agent, "P7DiscoveryCount", state.discoveryCount)
            debug(state.agent, "P7LastDiscoveredResourceId", observation.resourceId)
        end

        for _, report in pairs(state.resourceReports) do
            if report.resourceId == observation.resourceId then
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
                removeReport(state, report)
                break
            end
        end
    end

    setBelief(
        state,
        "threat_nearby",
        #observations.threats > 0,
        #observations.threats > 0 and 0.99 or 0.8,
        state.agent.Name,
        "direct",
        state.tick + 4
    )
end

local function scoutReport(state, observations)
    if state.role ~= Config.Roles.Scout then return end
    local sentAny, reported = false, 0
    for _, observation in ipairs(observations.resources) do
        if reported >= 3 then break end
        local lastTick = state.lastReportedResource[observation.resourceId] or -999
        if state.tick - lastTick >= 3 then
            SharedKnowledge.Publish(observation, state.tick, Config.SharedKnowledgeTTL)
            local sent = Communication.BroadcastResourceObservation(state.agent, state.folders.agents, state.tick, observation, Config)
            if sent > 0 then
                state.lastReportedResource[observation.resourceId] = state.tick
                reported += 1
                sentAny = true
            end
        end
    end
    if sentAny then
        state.folders.state:SetAttribute("P1_ScoutObserved", true)
        state.folders.state:SetAttribute("P1_ScoutSent", true)
        think(state, "สำรวจพบ Resource → ส่งข่าวให้ Colony")
    end
end

local function collectResource(state, observation)
    if state.role ~= Config.Roles.Gatherer then
        state.folders.state:SetAttribute("P1_RoleGuards", true)
        return false
    end
    local resource = observation and observation.instance
    if not resource or not resource.Parent or resource:GetAttribute("Active") == false then return false end
    if observation.distance > Config.CollectDistance or state.inventory:IsFull() then return false end

    local resourceType = resource:GetAttribute("ResourceType") or observation.subtype or "Wood"
    local accepted = state.inventory:Add(resourceType, resource:GetAttribute("Amount") or 1)
    if accepted <= 0 then return false end

    resource:SetAttribute("Active", false)
    resource.Transparency = 1
    resource.CanQuery = false
    updateInventoryDebug(state)
    state.folders.state:SetAttribute("P1_Collected", true)
    state.folders.state:SetAttribute("P2_CarryObserved", true)
    state.folders.state:SetAttribute("P2_LastCarriedType", resourceType)
    remember(state, "resource_carried", {
        sourceType = "legacy_physical",
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

    task.delay(Config.ResourceRespawnSeconds, function()
        if resource.Parent then
            resource.Transparency = 0
            resource.CanQuery = true
            resource:SetAttribute("Active", true)
        end
    end)
    return true
end

local function selectGatherTarget(state, observations)
    if state.preferredResourceType then
        for _, observation in ipairs(observations.resources) do
            if observation.subtype == state.preferredResourceType then return observation end
        end
    end
    return observations.resources[1]
end

local function gatherFromLivingWorld(state)
    if not state.worldBridge or state.role ~= Config.Roles.Gatherer or state.inventory:IsFull() then return false end
    local resourceType = state.preferredResourceType or "Wood"
    if resourceType ~= "Food" and resourceType ~= "Wood" then return false end

    local atSource, nav = w6Navigate(state, resourceType, "Living World → กำลังไปเก็บ " .. resourceType)
    if not atSource then return nav and nav.ok == true end

    local harvestOpts = nil
    if ProfessionAdapter.IsActionAllowed(state.role, "HarvestQuote") then
        harvestOpts = i6HarvestOpts(state, resourceType)
    end
    local tx = state.worldBridge.HarvestToInventory(
        state.agent.Name,
        state.inventory,
        state.root.Position,
        resourceType,
        1,
        w6TransactionId(state, "harvest", resourceType),
        harvestOpts
    )
    if tx.ok and not tx.duplicate then
        addWorldProvenance(state, resourceType, tx.actual)
        updateInventoryDebug(state)
        state.folders.state:SetAttribute("W6_WorldHarvestObserved", true)
        state.folders.state:SetAttribute("P2_CarryObserved", true)
        state.folders.state:SetAttribute("P2_LastCarriedType", resourceType)
        state.folders.state:SetAttribute("I3_ShadowHarvestObserved", tx.shadow ~= nil and tx.shadow.ok == true)
        if tx.receipt then
            debug(state.agent, "I3LastReceiptId", tx.receipt.transactionId)
            debug(state.agent, "I3LastSourceKind", tx.receipt.sourceKind)
        end
        if tx.shadowError then
            debug(state.agent, "I3ShadowError", tostring(tx.shadowError))
        end
        debug(state.agent, "W6LastTransaction", tx.transactionId)
        -- I6: P7 outcome on harvest committed only (not navigation / failed attempts).
        local harvestOutcome = P7OutcomeSink.FromHarvest(tx, state.agent.Name)
        if harvestOutcome then
            i6NotifyOutcome(harvestOutcome)
            state.folders.state:SetAttribute("I6_HarvestOutcomeObserved", true)
        end
        remember(state, "resource_carried", {
            sourceType = "living_world",
            resourceType = resourceType,
            amount = tx.actual,
            transactionId = tx.transactionId,
            position = state.root.Position,
            i3Shadowed = tx.shadow ~= nil and tx.shadow.ok == true,
            i6ToolClass = harvestOpts and harvestOpts.toolClass or nil,
        }, 0.95)
        return true
    end
    return false
end

local function deliverMaterials(state)
    if state.role ~= Config.Roles.Gatherer then return false end
    local active = Construction.GetActive()
    if not active then return false end

    local hasDelivery = false
    for _, resourceType in ipairs(ResourceEconomy.Types()) do
        if state.inventory:Get(resourceType) > 0 and ResourceEconomy.IsRequestedForBuild(state.folders.state, resourceType) then
            hasDelivery = true
            break
        end
    end
    if not hasDelivery then return false end

    if (active.position - state.root.Position).Magnitude > Config.BuildSiteDeliveryDistance then
        think(state, "ขนวัสดุไป Build Site")
        pathMove(state, active.position)
        return true
    end

    local delivered = {}
    local worldDelivered = 0
    for _, resourceType in ipairs(ResourceEconomy.Types()) do
        local carried = state.inventory:Get(resourceType)
        local missing = ResourceEconomy.GetBuildMissing(state.folders.state, resourceType)
        if carried > 0 and missing > 0 then
            local accepted = ResourceEconomy.DeliverToBuildSite(state.folders.state, resourceType, math.min(carried, missing))
            if accepted > 0 then
                state.inventory:Remove(resourceType, accepted)
                local worldAmount = consumeWorldProvenance(state, resourceType, accepted)
                worldDelivered += worldAmount
                if worldAmount > 0 then
                    InventoryShadow.RemoveLegacyProjection(
                        state.agent.Name,
                        resourceType,
                        worldAmount,
                        nextI3Tx(state, "deliver", resourceType),
                        resourceType == "Food" and { context = { source = "forage" } } or nil
                    )
                end
                table.insert(delivered, resourceType .. "+" .. tostring(accepted))
            end
        end
    end
    updateInventoryDebug(state)

    if #delivered > 0 then
        state.folders.state:SetAttribute("P3_PhysicalDelivery", true)
        if worldDelivered > 0 then state.folders.state:SetAttribute("W6_WorldToBuildObserved", true) end
        remember(state, "build_material_delivered", {
            items = delivered,
            site = active.blueprint.id,
            livingWorldAmount = worldDelivered,
        }, 0.9)
    end
    return true
end

local function depositResources(state)
    if state.role ~= Config.Roles.Gatherer or state.inventory:GetTotal() <= 0 then return false end
    if deliverMaterials(state) then return true end

    local depositPosition = Storage.GetDepositPosition(state.storage)
    if (depositPosition - state.root.Position).Magnitude > Config.DepositDistance then
        think(state, string.format("ขนของ %d/%d กลับคลัง", state.inventory:GetTotal(), state.inventory.capacity))
        pathMove(state, depositPosition)
        return false
    end

    local snapshot = state.inventory:Snapshot()
    local depositedTotal = 0
    local worldDeposited = 0
    local summary = {}
    for resourceType, amount in pairs(snapshot) do
        local accepted = ResourceEconomy.DepositToStorage(state.folders.state, resourceType, amount)
        if accepted > 0 then
            state.inventory:Remove(resourceType, accepted)
            depositedTotal += accepted
            local worldAmount = consumeWorldProvenance(state, resourceType, accepted)
            worldDeposited += worldAmount
            if worldAmount > 0 then
                InventoryShadow.RemoveLegacyProjection(
                    state.agent.Name,
                    resourceType,
                    worldAmount,
                    nextI3Tx(state, "deposit", resourceType),
                    resourceType == "Food" and { context = { source = "forage" } } or nil
                )
            end
            table.insert(summary, resourceType .. "+" .. tostring(accepted))
            state.folders.state:SetAttribute("P2_Deposited_" .. resourceType, true)
        end
    end
    updateInventoryDebug(state)

    if depositedTotal > 0 then
        table.sort(summary)
        state.folders.state:SetAttribute("P2_DepositObserved", true)
        state.folders.state:SetAttribute("P2_LastDeposit", table.concat(summary, ","))
        if worldDeposited > 0 then
            state.folders.state:SetAttribute("W6_WorldToColonyObserved", true)
            state.folders.state:SetAttribute("W6_LastWorldToColonyAmount", worldDeposited)
        end
        remember(state, "resource_deposited", {
            sourceType = worldDeposited > 0 and "mixed_or_living_world" or "legacy_physical",
            items = summary,
            livingWorldAmount = worldDeposited,
        }, 0.9)
        return true
    end
    return false
end

local function executeExplore(state)
    think(state, state.preferredResourceType and ("ค้นหา " .. state.preferredResourceType) or "สำรวจพื้นที่")
    pathMove(state, deterministicExplorePosition(state))
end

local function executeGather(state, observations)
    local target = selectGatherTarget(state, observations)
    if target and (not state.preferredResourceType or target.subtype == state.preferredResourceType) then
        if target.distance <= Config.CollectDistance then collectResource(state, target)
        else
            think(state, "เห็น " .. target.subtype .. " → กำลังไปเก็บ")
            pathMove(state, target.position)
        end
        return
    end

    local report = state.preferredResourceType and state.resourceReports[state.preferredResourceType] or state.resourceReport
    if report then
        if state.tick > report.expiresTick then
            state.expiredMessages += 1
            invalidateReport(state, report, "expired", false)
            return
        end
        if (report.position - state.root.Position).Magnitude > Config.ArrivalDistance then
            state.folders.state:SetAttribute("P1_RemoteGoal", true)
            pathMove(state, report.position)
            return
        end
        state.folders.state:SetAttribute("P1_MissingRecovered", true)
        invalidateReport(state, report, "not_found_on_arrival", true)
        return
    end

    if gatherFromLivingWorld(state) then return end
    executeExplore(state)
end

local function executeFlee(state, observations)
    -- I0.1: world-cell danger first requests a safe logical W5 route; the
    -- Roblox path execution below stays the physical transport.
    local worldDanger = observations.worldDanger
    if worldDanger and (worldDanger.effectiveDanger or 0) >= (Config.WorldDangerFleeThreshold or 0.5) then
        state.folders.state:SetAttribute("P4_SafetyResponse", true)
        state.folders.state:SetAttribute("W6_WorldEscapeObserved", true)
        if state.worldBridge and state.worldBridge.Escape then
            local escape = state.worldBridge.Escape(state.root.Position)
            if escape.ok and escape.nextPosition then
                debug(state.agent, "W6EscapeTarget", escape.nextPosition)
                pathMove(state, escape.nextPosition, true)
                return
            end
            debug(state.agent, "W6EscapeReason", escape.reason or "no_route")
        end
    end

    local threat = observations.threats[1]
    if not threat then return end
    local away = state.root.Position - threat.position
    if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
    state.folders.state:SetAttribute("P4_SafetyResponse", true)
    directMove(state, state.root.Position + away.Unit * 24, Config.RunSpeed)
end

local function storagePosition(state)
    return Storage.GetDepositPosition(state.storage)
end

local function executeEat(state)
    if state.inventory:Get("Food") > 0 then
        state.inventory:Remove("Food", 1)
        consumeWorldProvenance(state, "Food", 1)
        Needs.Eat(state.needs, Config)
        updateInventoryDebug(state)
        state.folders.state:SetAttribute("P4_EatObserved", true)
        return
    end

    if ResourceEconomy.Get(state.folders.state, "Food") > 0 then
        if (storagePosition(state) - state.root.Position).Magnitude > Config.SurvivalUseDistance then
            pathMove(state, storagePosition(state))
            return
        end
        if ResourceEconomy.Consume(state.folders.state, "Food", 1) > 0 then
            Needs.Eat(state.needs, Config)
            state.folders.state:SetAttribute("P4_EatObserved", true)
        end
        return
    end

    if not state.worldBridge then return end
    local atSource, nav = w6Navigate(state, "Food", "คลังไม่มี Food → ไปหาอาหารจาก Living World")
    if not atSource then return end

    local tx = state.worldBridge.TryEat(
        state.agent.Name,
        state.root.Position,
        w6TransactionId(state, "eat", "Food")
    )
    if tx.ok and not tx.duplicate then
        Needs.Eat(state.needs, Config)
        state.folders.state:SetAttribute("P4_EatObserved", true)
        state.folders.state:SetAttribute("W6_WorldEatObserved", true)
        debug(state.agent, "W6LastTransaction", tx.transactionId)
    elseif not (nav and nav.ok) then
        debug(state.agent, "W6WorldTargetReason", tx.reason or "eat_failed")
    end
end

local function executeDrink(state)
    if state.inventory:Get("Water") > 0 then
        state.inventory:Remove("Water", 1)
        consumeWorldProvenance(state, "Water", 1)
        Needs.Drink(state.needs, Config)
        updateInventoryDebug(state)
        state.folders.state:SetAttribute("P4_DrinkObserved", true)
        return
    end

    if ResourceEconomy.Get(state.folders.state, "Water") > 0 then
        if (storagePosition(state) - state.root.Position).Magnitude > Config.SurvivalUseDistance then
            pathMove(state, storagePosition(state))
            return
        end
        if ResourceEconomy.Consume(state.folders.state, "Water", 1) > 0 then
            Needs.Drink(state.needs, Config)
            state.folders.state:SetAttribute("P4_DrinkObserved", true)
        end
        return
    end

    if not state.worldBridge then return end
    local atSource = w6Navigate(state, "Water", "คลังไม่มี Water → ไปหาแหล่งน้ำจาก Living World")
    if not atSource then return end

    local tx = state.worldBridge.TryDrink(
        state.agent.Name,
        state.root.Position,
        w6TransactionId(state, "drink", "Water")
    )
    if tx.ok and not tx.duplicate then
        Needs.Drink(state.needs, Config)
        state.folders.state:SetAttribute("P4_DrinkObserved", true)
        state.folders.state:SetAttribute("W6_WorldDrinkObserved", true)
        debug(state.agent, "W6LastTransaction", tx.transactionId)
    end
end

local function executeRest(state)
    local shelter = state.folders.structures:FindFirstChild("Shelter")
    local restPosition = shelter and shelter.Position or storagePosition(state)
    local inShelter = shelter ~= nil
    if (restPosition - state.root.Position).Magnitude > Config.SurvivalUseDistance then
        pathMove(state, restPosition)
        return
    end
    state.humanoid:MoveTo(state.root.Position)
    Needs.Rest(state.needs, Config, inShelter)
    state.folders.state:SetAttribute("P4_RestObserved", true)
    state.folders.state:SetAttribute("P4_RestedInShelter", inShelter)
end

local function executeSocialize(state, observations)
    local nearest = observations.agents[1]
    if nearest then
        if nearest.distance > Config.SocialDistance then
            pathMove(state, nearest.position)
            return
        end
        Needs.Socialize(state.needs, Config)
        state.folders.state:SetAttribute("P4_SocialObserved", true)
        remember(state, "socialized", { with = nearest.instance.Name }, 0.6)
        return
    end
    pathMove(state, storagePosition(state))
end

local function executeWaitFor(state, resourceType)
    if (storagePosition(state) - state.root.Position).Magnitude > Config.SurvivalUseDistance then
        pathMove(state, storagePosition(state))
    else
        state.humanoid:MoveTo(state.root.Position)
    end
    think(state, "รอ " .. resourceType .. " ที่คลัง")
end

local function executeBuildViaB1(state)
    if not ProfessionAdapter.IsActionAllowed(state.role, "B1Place") then
        return false
    end
    local part = ProfessionAdapter.PickPlaceableBuildPart(state.agent.Name)
    if not part then
        return false
    end

    local buildingFolder = game:GetService("ServerScriptService"):FindFirstChild("AstraBuilding")
    if not buildingFolder then
        return false
    end
    local okRequire, BuildingLifecycleService = pcall(function()
        return require(buildingFolder:FindFirstChild("BuildingLifecycleService"))
    end)
    if not okRequire or not BuildingLifecycleService then
        return false
    end

    -- Place near the agent using shared SurfaceResolver path inside B1 Preview/Place (W5 gated).
    local target = state.root.Position + Vector3.new(6, 0, 0)
    state.i6BuildTxSeq = (state.i6BuildTxSeq or 0) + 1
    local transactionId = string.format(
        "i6:place:%s:%s:%d:%d",
        state.agent.Name,
        part.itemId,
        state.tick,
        state.i6BuildTxSeq
    )

    think(state, "I5 B1 → วาง " .. part.itemId)
    local placed, reason = ProfessionAdapter.PlaceCraftedPart(BuildingLifecycleService, {
        actorId = state.agent.Name,
        itemId = part.itemId,
        position = target,
        yawDegrees = 0,
        transactionId = transactionId,
    })
    if placed and placed.ok then
        state.folders.state:SetAttribute("I6_BuilderB1PlaceObserved", true)
        state.folders.state:SetAttribute("I5_BuilderUsesB1", true)
        debug(state.agent, "I6LastBuildPiece", placed.pieceId)
        local outcome = P7OutcomeSink.FromBuilding(placed)
        if outcome then
            i6NotifyOutcome(outcome)
        end
        remember(state, "structure_built", {
            sourceType = "b1_place",
            pieceId = placed.pieceId,
            pieceType = placed.pieceType,
            itemId = part.itemId,
            transactionId = transactionId,
            position = target,
        }, 1.0)
        return true
    end

    debug(state.agent, "I6BuildPlaceReason", tostring(reason or "place_failed"))
    -- If preview rejected (W5 wet/steep), try compatibility Construction path.
    return false
end

local function executeBuild(state)
    if state.role ~= Config.Roles.Builder then return end

    -- I6: prefer I5 B1 placement when crafted S4 build parts exist.
    if executeBuildViaB1(state) then
        return
    end

    -- Compatibility: legacy P3 Construction.lua remains (dual-truth with B1; soak via I6_BuilderUsedP3Fallback).
    local active = Construction.GetActive()
    if not active then
        local blueprint = Construction.GetNextBlueprint(state.folders, Config)
        if not blueprint then return end
        active = Construction.TryStart(state.agent, state.folders, Config, state.tick)
    end
    if not active then return end

    if (active.position - state.root.Position).Magnitude > Config.ArrivalDistance + 2 then
        pathMove(state, active.position)
        return
    end

    -- Compatibility dual-truth: Builder is on the legacy P3 Construction path.
    state.folders.state:SetAttribute("I6_BuilderUsedP3Fallback", true)
    state.agent:SetAttribute("I6_BuilderUsedP3Fallback", true)

    local ok, status, detail = Construction.Step(state.agent, state.folders, Config, state.tick)
    if ok and status == "completed" then
        remember(state, "structure_built", {
            sourceType = "self_action",
            blueprint = active.blueprint.id,
            position = active.position,
        }, 1.0)
        state.folders.state:SetAttribute("I6_BuilderUsedP3Fallback", true)
        -- Outcome for legacy completion (deduped by blueprint id). SkillLearning skips
        -- builder_complete under P7_I6OutcomeOnly so this is the sole XP authority.
        i6NotifyOutcome({
            eventName = "BuildingCompleted",
            kind = "building_completed",
            transactionId = "p3:complete:" .. tostring(active.blueprint.id),
            actorId = state.agent.Name,
        })
    elseif status == "too_far" and typeof(detail) == "Vector3" then
        pathMove(state, detail)
    end
end

local function updateStuck(state)
    local moved = (state.root.Position - state.lastPosition).Magnitude
    if state.targetPosition and (state.targetPosition - state.root.Position).Magnitude > Config.ArrivalDistance then
        state.stuckTicks = moved <= Config.StuckDistanceEpsilon and (state.stuckTicks + 1) or 0
    else
        state.stuckTicks = 0
    end
    state.lastPosition = state.root.Position
    debug(state.agent, "StuckTicks", state.stuckTicks)

    if state.stuckTicks >= Config.StuckTicksBeforePath and state.targetPosition then
        pathMove(state, state.targetPosition, true)
        state.stuckTicks = 0
    end
end

local function executeGoal(state, goal, observations)
    debug(state.agent, "Goal", goal)
    if goal == "Flee" then executeFlee(state, observations)
    elseif goal == "Eat" then state.folders.state:SetAttribute("P4_SurvivalGoalObserved", true) executeEat(state)
    elseif goal == "Drink" then state.folders.state:SetAttribute("P4_SurvivalGoalObserved", true) executeDrink(state)
    elseif goal == "Rest" then state.folders.state:SetAttribute("P4_SurvivalGoalObserved", true) executeRest(state)
    elseif goal == "Socialize" then state.folders.state:SetAttribute("P4_SurvivalGoalObserved", true) executeSocialize(state, observations)
    elseif goal == "WaitForFood" then executeWaitFor(state, "Food")
    elseif goal == "WaitForWater" then executeWaitFor(state, "Water")
    elseif goal == "GatherResource" then executeGather(state, observations)
    elseif goal == "DeliverMaterials" then if not deliverMaterials(state) then depositResources(state) end
    elseif goal == "DepositResources" then depositResources(state)
    elseif goal == "BuildStructure" then executeBuild(state)
    elseif goal == "Communicate" then
        if state.role == Config.Roles.Scout then scoutReport(state, observations) else executeExplore(state) end
    else executeExplore(state) end
end

function BrainIntegrated.Start(agent, services)
    if runningAgents[agent] then return runningAgents[agent] end
    local humanoid = agent:FindFirstChildOfClass("Humanoid")
    local root = agent:FindFirstChild("HumanoidRootPart")
    local head = agent:FindFirstChild("Head")
    if not humanoid or not root or not head then return nil end

    local folders = WorldState.Ensure(Config)
    ResourceEconomy.Ensure(folders.state, Config.StorageCapacity)
    local role = inferRole(agent)
    agent:SetAttribute("Role", role)
    agent:SetAttribute("IsAstraAgent", true)
    humanoid.DisplayName = agent.Name
    humanoid.WalkSpeed = Config.WalkSpeed
    for _, obj in ipairs(agent:GetDescendants()) do
        if obj:IsA("BasePart") then obj.Anchored = false end
    end
    if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end

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
        resourceReports = {},
        preferredResourceType = nil,
        processedMessages = {},
        processedObservations = {},
        duplicateMessages = 0,
        expiredMessages = 0,
        lastReportedResource = {},
        needs = Needs.Create(Config),
        lastPathTarget = nil,
        lastPathComputeTick = nil,
        cachedWaypoints = nil,
        cachedWaypointIndex = nil,
        pathComputeCount = 0,
        pathCacheHits = 0,
        worldBridge = services and services.survivalBridge or nil,
        worldCarried = {},
        i3TxSeq = 0,
        discoveredResources = {},
        discoveryCount = 0,
    }

    runningAgents[agent] = state
    debug(agent, "State", "Online")
    debug(agent, "RuntimeVersion", Config.RuntimeVersion)
    debug(agent, "DuplicateMessagesDropped", 0)
    debug(agent, "ExpiredBeliefs", 0)
    debug(agent, "PathComputeCount", 0)
    debug(agent, "PathCacheHits", 0)
    debug(agent, "P7DiscoveryCount", 0)
    debug(agent, "W6BridgeEnabled", state.worldBridge ~= nil)
    updateInventoryDebug(state)
    Needs.SyncAgent(agent, state.needs, Config)
    if role ~= Config.Roles.Gatherer then folders.state:SetAttribute("P1_RoleGuards", true) end
    think(state, "AstraBrain P7.5 + W7 integration online")

    humanoid.Died:Connect(function() runningAgents[agent] = nil end)

    task.spawn(function()
        while runningAgents[agent] == state and agent.Parent and humanoid.Health > 0 do
            task.wait(Config.TickSeconds)
            state.tick = WorldState.GetTick(Config)
            state.localDecisionTick += 1
            debug(agent, "Tick", state.tick)
            debug(agent, "LocalDecisionTick", state.localDecisionTick)

            local liveRole = agent:GetAttribute("Role")
            if liveRole and liveRole ~= "Unassigned" and liveRole ~= state.role then
                state.role = liveRole
                debug(agent, "BrainRole", liveRole)
                debug(agent, "BrainRoleSyncTick", state.tick)
            end

            cleanupExpiringMap(state.processedMessages, state.tick)
            cleanupExpiringMap(state.processedObservations, state.tick)

            local expiredReports = {}
            for _, report in pairs(state.resourceReports) do
                if state.tick > report.expiresTick then table.insert(expiredReports, report) end
            end
            for _, report in ipairs(expiredReports) do
                state.expiredMessages += 1
                invalidateReport(state, report, "expired", false)
            end

            processMessages(state)
            local observations = Perception.Observe(agent, folders, Config, state.tick)

            -- I0.1: read the Living World cell danger through the single
            -- W-series observation contract; no second hazard authority here.
            if state.worldBridge and state.worldBridge.ObserveEnvironment then
                local worldDanger = state.worldBridge.ObserveEnvironment(state.root.Position)
                observations.worldDanger = worldDanger
                debug(agent, "W6EnvironmentDanger", worldDanger.effectiveDanger or 0)
                debug(agent, "W6DominantHazard", worldDanger.dominantHazard or "none")
                if (worldDanger.effectiveDanger or 0) >= (Config.WorldDangerFleeThreshold or 0.5) then
                    agent:SetAttribute("W6WorldDangerCritical", true)
                    folders.state:SetAttribute("W6_WorldDangerObserved", true)
                end
                setBelief(state, "world_danger", (worldDanger.effectiveDanger or 0) >= (Config.WorldDangerFleeThreshold or 0.5),
                    worldDanger.effectiveDanger or 0, "living_world", "W6", state.tick + 4)
            end

            updateBeliefsFromObservation(state, observations)

            local worldSafetyLoss = 0
            if observations.worldDanger then
                worldSafetyLoss = (observations.worldDanger.effectiveDanger or 0) * (Config.WorldDangerSafetyLossPerTick or 8)
            end
            local critical = Needs.Tick(state.needs, humanoid, #observations.threats > 0, Config, worldSafetyLoss)
            Needs.SyncAgent(agent, state.needs, Config)
            folders.state:SetAttribute("P4_NeedsDecayed", true)
            if critical then folders.state:SetAttribute("P4_CriticalDamageObserved", true) end

            state.expiredMessages += state.belief:Decay(state.tick)
            debug(agent, "ExpiredBeliefs", state.expiredMessages)
            if state.role == Config.Roles.Scout then scoutReport(state, observations) end
            debug(agent, "KnownResourceCount", SharedKnowledge.ActiveCount(state.tick))

            local goal, score = Planner.ChooseGoal(state, observations, Construction, ResourceEconomy, Config)
            debug(agent, "GoalScore", score)
            debug(agent, "Plan", goal)
            executeGoal(state, goal, observations)
            Needs.SyncAgent(agent, state.needs, Config)
            updateStuck(state)
        end
    end)

    return state
end

return BrainIntegrated

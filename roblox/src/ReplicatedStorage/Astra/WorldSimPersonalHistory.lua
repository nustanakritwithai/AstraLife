local WorldSimPersonalHistory = {}

local MAX_EVENTS = 40
local histories = {}
local observed = {}

local function stateFor(agent)
    local name = agent.Name
    if not histories[name] then histories[name] = {} end
    if not observed[name] then
        observed[name] = {
            role = agent:GetAttribute("Role"),
            critical = agent:GetAttribute("SurvivalCritical") == true,
        }
    end
    return histories[name], observed[name]
end

function WorldSimPersonalHistory.Record(agent, tick, eventType, text, importance)
    local history = stateFor(agent)
    table.insert(history, {
        tick = tick,
        eventType = eventType,
        text = text,
        importance = importance or 0.5,
    })
    while #history > MAX_EVENTS do table.remove(history, 1) end
    agent:SetAttribute("LifeEventCount", #history)
    agent:SetAttribute("LastLifeEvent", text)
    agent:SetAttribute("LastLifeEventType", eventType)
    agent:SetAttribute("LastLifeEventTick", tick)
end

function WorldSimPersonalHistory.Observe(agent, tick)
    local _, state = stateFor(agent)
    local transitions = 0
    local role = agent:GetAttribute("Role")
    local critical = agent:GetAttribute("SurvivalCritical") == true

    if role ~= state.role then
        WorldSimPersonalHistory.Record(agent, tick, "career", string.format("Role changed %s -> %s", tostring(state.role), tostring(role)), 0.8)
        state.role = role
        transitions += 1
    end

    if critical ~= state.critical then
        WorldSimPersonalHistory.Record(
            agent,
            tick,
            critical and "survival_crisis" or "recovery",
            critical and "Entered survival critical state" or "Recovered from survival critical state",
            critical and 1 or 0.8
        )
        state.critical = critical
        transitions += 1
    end

    return transitions
end

function WorldSimPersonalHistory.Get(agentName)
    local source = histories[agentName] or {}
    local out = {}
    for i, entry in ipairs(source) do out[i] = table.clone(entry) end
    return out
end

return WorldSimPersonalHistory

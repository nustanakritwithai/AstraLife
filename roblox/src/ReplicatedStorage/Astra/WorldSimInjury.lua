local Determinism = require(script.Parent.WorldSimDeterminism)

local WorldSimInjury = {}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function classify(severity, cause)
    if severity <= 0 then return "None" end
    if cause == "survival" then return severity >= 40 and "SevereExhaustion" or "Exhaustion" end
    if cause == "danger" then return severity >= 40 and "MajorTrauma" or "MinorTrauma" end
    return severity >= 40 and "MajorInjury" or "MinorInjury"
end

function WorldSimInjury.Ensure(agent)
    if agent:GetAttribute("InjurySeverity") == nil then agent:SetAttribute("InjurySeverity", 0) end
    if agent:GetAttribute("InjuryType") == nil then agent:SetAttribute("InjuryType", "None") end
    if agent:GetAttribute("InjuryCause") == nil then agent:SetAttribute("InjuryCause", "None") end
end

function WorldSimInjury.Tick(agent, worldState, tick, seed)
    WorldSimInjury.Ensure(agent)
    local severity = agent:GetAttribute("InjurySeverity") or 0
    local critical = agent:GetAttribute("SurvivalCritical") == true
    local safety = agent:GetAttribute("Safety") or 100
    local danger = worldState:GetAttribute("DangerActive") == true
    local cause = nil

    if critical then
        local roll = Determinism.Random01(seed, agent.Name .. ":injury:survival", tick)
        if roll < 0.12 then
            severity += Determinism.Range(seed, agent.Name .. ":injury:survival:severity", tick, 5, 13)
            cause = "survival"
        end
    elseif danger and safety < 50 then
        local roll = Determinism.Random01(seed, agent.Name .. ":injury:danger", tick)
        if roll < 0.08 then
            severity += Determinism.Range(seed, agent.Name .. ":injury:danger:severity", tick, 4, 11)
            cause = "danger"
        end
    end

    if not cause then
        if agent:GetAttribute("Goal") == "Rest" and not critical then
            severity -= 2
        elseif not danger and safety >= 60 then
            severity -= 0.25
        end
    end

    severity = clamp(severity, 0, 100)
    local injuryType = classify(severity, cause or agent:GetAttribute("InjuryCause"))
    if severity <= 0 then cause = "None" end

    local previous = agent:GetAttribute("InjurySeverity") or 0
    agent:SetAttribute("InjurySeverity", math.floor(severity * 10 + 0.5) / 10)
    agent:SetAttribute("InjuryType", injuryType)
    if cause then agent:SetAttribute("InjuryCause", cause) end
    agent:SetAttribute("Injured", severity > 0)

    if severity > previous + 0.01 then
        agent:SetAttribute("LastInjuryTick", tick)
        return {
            agent = agent.Name,
            severity = severity,
            injuryType = injuryType,
            cause = cause,
        }
    end
    return nil
end

return WorldSimInjury

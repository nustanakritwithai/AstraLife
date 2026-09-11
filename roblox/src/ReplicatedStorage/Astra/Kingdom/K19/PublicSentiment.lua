local PublicSentiment = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function PublicSentiment.Evaluate(snapshot, events, currentTick, kingdomRoot)
    local pop = math.max(1, snapshot.population.total)
    local criticalRatio = snapshot.population.critical / pop
    local safety = clamp(snapshot.population.averageSafety / 100, 0, 1)
    local social = clamp(snapshot.population.averageSocial / 100, 0, 1)
    local health = clamp(snapshot.population.averageHealthRatio, 0, 1)
    local reserve = clamp((snapshot.stocks.Total or 0) / math.max(1, snapshot.stocks.Capacity or 1), 0, 1)

    local governance = kingdomRoot and kingdomRoot:FindFirstChild("K5Governance")
    local legitimacy = governance and ((governance:GetAttribute("Legitimacy") or 50) / 100) or 0.5
    local crime = kingdomRoot and kingdomRoot:FindFirstChild("K15CrimeEconomy")
    local crimePressure = crime and ((crime:GetAttribute("CrimePressure") or 0) / 100) or 0

    local eventDelta, fearDelta, grievanceDelta = 0, 0, 0
    for _, event in ipairs(events or {}) do
        local age = math.max(0, currentTick - (event.tick or currentTick))
        local weight = math.max(0, 1 - age / 120)
        local magnitude = clamp(tonumber(event.magnitude) or 0, -1, 1) * weight
        eventDelta += magnitude
        if event.kind == "danger" or event.kind == "disaster" or event.kind == "defeat" then
            fearDelta += math.abs(magnitude)
        elseif event.kind == "corruption" or event.kind == "shortage" or event.kind == "betrayal" then
            grievanceDelta += math.abs(magnitude)
        end
    end
    eventDelta = clamp(eventDelta * 0.12, -0.35, 0.35)
    fearDelta = clamp(fearDelta * 0.12, 0, 0.35)
    grievanceDelta = clamp(grievanceDelta * 0.12, 0, 0.35)

    local support = clamp(safety * 0.2 + social * 0.15 + health * 0.15 + reserve * 0.15 + legitimacy * 0.25 + (1 - crimePressure) * 0.1 + eventDelta, 0, 1)
    local fear = clamp((1 - safety) * 0.45 + criticalRatio * 0.25 + crimePressure * 0.2 + fearDelta, 0, 1)
    local grievance = clamp((1 - reserve) * 0.25 + criticalRatio * 0.25 + (1 - legitimacy) * 0.3 + crimePressure * 0.1 + grievanceDelta, 0, 1)
    local loyalty = clamp(support * 0.65 + social * 0.2 + legitimacy * 0.15 - grievance * 0.25, 0, 1)

    local state = "CONTENT"
    if grievance >= 0.75 then state = "HOSTILE"
    elseif fear >= 0.7 then state = "FEARFUL"
    elseif support < 0.4 then state = "DISCONTENT"
    elseif support >= 0.75 and loyalty >= 0.7 then state = "LOYAL" end

    return {
        PublicSupport = support * 100,
        PublicFear = fear * 100,
        PublicGrievance = grievance * 100,
        PublicLoyalty = loyalty * 100,
        LegitimacySignal = legitimacy * 100,
        ActiveEventCount = #(events or {}),
        SentimentState = state,
    }
end

return PublicSentiment

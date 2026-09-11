local Belief = {}
Belief.__index = Belief

function Belief.new(config)
    return setmetatable({
        config = config,
        values = {},
    }, Belief)
end

function Belief:Set(tick, key, value, confidence, source, provenance, expiresTick)
    local current = self.values[key]
    local nextBelief = {
        value = value,
        confidence = math.clamp(confidence or 0.5, 0, 1),
        source = source or "unknown",
        provenance = provenance or "unknown",
        updatedTick = tick,
        expiresTick = expiresTick,
        valid = true,
    }

    if current and current.valid ~= false then
        local incomingIsDirect = nextBelief.provenance == "direct"
        local currentIsDirect = current.provenance == "direct"
        if current.updatedTick > tick then
            return current
        end
        if current.updatedTick == tick and currentIsDirect and not incomingIsDirect then
            return current
        end
        if current.updatedTick == tick and current.confidence > nextBelief.confidence and currentIsDirect == incomingIsDirect then
            return current
        end
    end

    self.values[key] = nextBelief
    return nextBelief
end

function Belief:Get(key, currentTick)
    local belief = self.values[key]
    if not belief or belief.valid == false then
        return nil
    end
    if currentTick and belief.expiresTick and currentTick > belief.expiresTick then
        belief.valid = false
        return nil
    end
    return belief
end

function Belief:GetAll(currentTick)
    local out = {}
    for key, belief in pairs(self.values) do
        if belief.valid ~= false and (not currentTick or not belief.expiresTick or currentTick <= belief.expiresTick) then
            out[key] = belief
        end
    end
    return out
end

function Belief:GetByPrefix(prefix, currentTick)
    local out = {}
    for key, belief in pairs(self.values) do
        if string.sub(key, 1, #prefix) == prefix
            and belief.valid ~= false
            and (not currentTick or not belief.expiresTick or currentTick <= belief.expiresTick) then
            out[key] = belief
        end
    end
    return out
end

function Belief:Invalidate(key, tick, reason)
    local belief = self.values[key]
    if not belief then
        return false
    end
    belief.valid = false
    belief.invalidatedTick = tick
    belief.invalidReason = reason or "invalidated"
    return true
end

function Belief:Decay(tick)
    local expired = 0
    for _, belief in pairs(self.values) do
        if belief.valid ~= false then
            if belief.expiresTick and tick > belief.expiresTick then
                belief.valid = false
                expired += 1
            else
                local age = tick - belief.updatedTick
                if age > self.config.BeliefDecayAfterTicks then
                    belief.confidence = math.max(0, belief.confidence - self.config.BeliefDecayPerTick)
                    if belief.confidence <= 0 then
                        belief.valid = false
                        expired += 1
                    end
                end
            end
        end
    end
    return expired
end

return Belief

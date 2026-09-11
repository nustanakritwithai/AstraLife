local Belief = {}
Belief.__index = Belief

function Belief.new(config)
    return setmetatable({
        config = config,
        values = {},
    }, Belief)
end

function Belief:Set(tick, key, value, confidence, source)
    self.values[key] = {
        value = value,
        confidence = math.clamp(confidence or 0.5, 0, 1),
        source = source or "unknown",
        updatedTick = tick,
    }

    return self.values[key]
end

function Belief:Get(key)
    return self.values[key]
end

function Belief:Decay(tick)
    for _, belief in pairs(self.values) do
        local age = tick - belief.updatedTick
        if age > self.config.BeliefDecayAfterTicks then
            belief.confidence = math.max(0.1, belief.confidence - self.config.BeliefDecayPerTick)
        end
    end
end

return Belief

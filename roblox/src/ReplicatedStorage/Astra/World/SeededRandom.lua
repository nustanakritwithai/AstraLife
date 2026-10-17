local SeededRandom = {}
SeededRandom.__index = SeededRandom

local MODULUS = 4294967296
local MULTIPLIER = 1664525
local INCREMENT = 1013904223

local function hashString(value)
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % MODULUS
    end
    return hash
end

local function normalizeSeed(seed)
    if type(seed) == "string" then
        return hashString(seed)
    end
    if type(seed) ~= "number" then
        seed = 1
    end
    return math.floor(math.abs(seed)) % MODULUS
end

function SeededRandom.new(seed)
    return setmetatable({
        _initialSeed = normalizeSeed(seed),
        _state = normalizeSeed(seed),
    }, SeededRandom)
end

function SeededRandom:GetInitialSeed()
    return self._initialSeed
end

function SeededRandom:GetState()
    return self._state
end

function SeededRandom:SetState(state)
    self._state = normalizeSeed(state)
end

function SeededRandom:Reset()
    self._state = self._initialSeed
end

function SeededRandom:NextUnit()
    self._state = (MULTIPLIER * self._state + INCREMENT) % MODULUS
    return self._state / MODULUS
end

function SeededRandom:NextNumber(minimum, maximum)
    minimum = minimum or 0
    maximum = maximum or 1
    if maximum < minimum then
        minimum, maximum = maximum, minimum
    end
    return minimum + (maximum - minimum) * self:NextUnit()
end

function SeededRandom:NextInteger(minimum, maximum)
    assert(type(minimum) == "number" and type(maximum) == "number", "minimum and maximum are required")
    minimum = math.floor(minimum)
    maximum = math.floor(maximum)
    if maximum < minimum then
        minimum, maximum = maximum, minimum
    end
    local span = maximum - minimum + 1
    return minimum + math.floor(self:NextUnit() * span)
end

function SeededRandom:Fork(label)
    local childSeed = (self._state + hashString(tostring(label)) + 2654435761) % MODULUS
    return SeededRandom.new(childSeed)
end

return SeededRandom

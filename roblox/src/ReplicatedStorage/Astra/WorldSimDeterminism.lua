local Determinism = {}

local MOD = 2147483647

local function mix(h, text)
    local s = tostring(text)
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % MOD
    end
    return (h * 33 + 124) % MOD
end

function Determinism.HashParts(...)
    local h = 5381
    for i = 1, select("#", ...) do
        h = mix(h, select(i, ...))
    end
    return h
end

function Determinism.Random01(seed, key, tick)
    return (Determinism.HashParts(seed or 1, key or "", tick or 0) % 1000000) / 1000000
end

function Determinism.Range(seed, key, tick, minValue, maxValue)
    local t = Determinism.Random01(seed, key, tick)
    return minValue + (maxValue - minValue) * t
end

function Determinism.Int(seed, key, tick, minValue, maxValue)
    return math.floor(Determinism.Range(seed, key, tick, minValue, maxValue + 1))
end

function Determinism.StableSort(items, keyFn)
    local decorated = {}
    for index, item in ipairs(items) do
        decorated[index] = {
            item = item,
            key = tostring(keyFn(item)),
            index = index,
        }
    end
    table.sort(decorated, function(a, b)
        if a.key == b.key then return a.index < b.index end
        return a.key < b.key
    end)
    local out = {}
    for index, entry in ipairs(decorated) do out[index] = entry.item end
    return out
end

function Determinism.Fingerprint(parts)
    local h = 5381
    for _, part in ipairs(parts) do
        h = mix(h, part)
    end
    return string.format("%08x", h)
end

return Determinism

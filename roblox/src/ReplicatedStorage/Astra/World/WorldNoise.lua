local WorldNoise = {}

local MODULUS = 2147483647

local function fract(value)
    return value - math.floor(value)
end

local function hash01(seed, x, z, channel)
    local n = (
        (seed or 1) * 48271
        + (x or 0) * 69621
        + (z or 0) * 90703
        + (channel or 0) * 104729
    ) % MODULUS
    n = (n * 48271 + 1) % MODULUS
    return n / MODULUS
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

function WorldNoise.Hash01(seed, x, z, channel)
    return hash01(seed, x, z, channel)
end

function WorldNoise.Value2D(seed, x, z, channel)
    local x0 = math.floor(x)
    local z0 = math.floor(z)
    local x1 = x0 + 1
    local z1 = z0 + 1

    local tx = smooth(fract(x))
    local tz = smooth(fract(z))

    local a = hash01(seed, x0, z0, channel)
    local b = hash01(seed, x1, z0, channel)
    local c = hash01(seed, x0, z1, channel)
    local d = hash01(seed, x1, z1, channel)

    return lerp(lerp(a, b, tx), lerp(c, d, tx), tz)
end

function WorldNoise.Fractal2D(seed, x, z, options)
    options = options or {}
    local octaves = math.max(1, math.floor(options.octaves or 4))
    local frequency = options.frequency or 0.08
    local persistence = options.persistence or 0.5
    local lacunarity = options.lacunarity or 2
    local channel = options.channel or 0

    local amplitude = 1
    local total = 0
    local normalization = 0

    for octave = 1, octaves do
        total += WorldNoise.Value2D(seed, x * frequency, z * frequency, channel + octave * 37) * amplitude
        normalization += amplitude
        amplitude *= persistence
        frequency *= lacunarity
    end

    if normalization <= 0 then
        return 0
    end
    return math.clamp(total / normalization, 0, 1)
end

return WorldNoise

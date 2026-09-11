local BiomeTerrainService = require(script.Parent.BiomeTerrainService)

local ok, result = pcall(function()
    return BiomeTerrainService.Start()
end)

if not ok then
    warn("[AstraLife/W1] biome terrain bootstrap failed:", result)
else
    print(string.format(
        "[AstraLife/W1] terrain ready cells=%d biomes=%d fingerprint=%s status=%s",
        result.stats.total,
        (function()
            local count = 0
            for _, amount in pairs(result.stats.biomes) do
                if amount > 0 then count += 1 end
            end
            return count
        end)(),
        result.fingerprint,
        result.passed and "PASS" or "FAIL"
    ))
end

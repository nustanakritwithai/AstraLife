local BuildingMapSeeder = require(script.Parent.BuildingMapSeeder)
local BuildingMapVerifier = require(script.Parent.BuildingMapVerifier)

local result = BuildingMapSeeder.Start()
local passed, _, stats = BuildingMapVerifier.Run(result)

print(string.format(
    "[AstraLife][B1/Map] seeded=%s status=%s pieces=%d rendered=%d runtime=%s",
    tostring(result.seeded),
    tostring(result.reason),
    tonumber(stats.graphCount) or 0,
    tonumber(stats.renderCount) or 0,
    passed and "PASS" or "FAIL"
))

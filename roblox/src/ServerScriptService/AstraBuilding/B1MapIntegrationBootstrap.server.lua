local BuildingMapSeeder = require(script.Parent.BuildingMapSeeder)

local result = BuildingMapSeeder.Start()
print(string.format(
    "[AstraLife][B1/Map] modular outpost seeded=%s status=%s pieces=%d",
    tostring(result.seeded),
    tostring(result.reason),
    tonumber(result.pieceCount) or 0
))

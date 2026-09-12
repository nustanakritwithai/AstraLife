local ModularBuildingService = require(script.Parent.ModularBuildingService)

local result = ModularBuildingService.Start()
print(string.format(
    "[AstraLife][B0] modular building online status=%s pieces=%d",
    tostring(result.state:GetAttribute("B0Status")),
    result.graph:Count()
))

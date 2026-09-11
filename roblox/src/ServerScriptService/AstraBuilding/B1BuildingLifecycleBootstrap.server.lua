local BuildingLifecycleService = require(script.Parent.BuildingLifecycleService)

local result = BuildingLifecycleService.Start()
print(string.format(
    "[AstraLife][B1] building lifecycle online status=%s",
    tostring(result.state:GetAttribute("B1Status"))
))

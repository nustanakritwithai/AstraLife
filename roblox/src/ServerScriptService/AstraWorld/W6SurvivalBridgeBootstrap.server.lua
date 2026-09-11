local SurvivalBridgeService = require(script.Parent.SurvivalBridgeService)

local result = SurvivalBridgeService.Start()
print(string.format(
    "[AstraLife][W6] survival bridge online status=%s",
    tostring(result.runtime.state:GetAttribute("W6Status"))
))

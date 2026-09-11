local EcosystemService = require(script.Parent.EcosystemService)

local result = EcosystemService.Start()
print(string.format(
    "[AstraLife][W7] ecosystem online status=%s",
    tostring(result.runtime.state:GetAttribute("W7Status"))
))

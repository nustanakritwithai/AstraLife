local AffordanceNavigationService = require(script.Parent.AffordanceNavigationService)

local result = AffordanceNavigationService.Start()
if result and result.runtime and result.runtime.state then
    result.runtime.state:SetAttribute("W5BootstrapReady", true)
end

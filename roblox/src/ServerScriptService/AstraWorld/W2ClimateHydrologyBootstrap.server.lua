local ClimateHydrologyService = require(script.Parent.ClimateHydrologyService)

local ok, result = pcall(function()
    return ClimateHydrologyService.Start()
end)

if not ok then
    warn("[AstraLife][W2] Climate/Hydrology bootstrap failed: " .. tostring(result))
else
    local runtime = result and result.runtime
    if runtime and runtime.state then
        runtime.state:SetAttribute("W2BootstrapReady", true)
    end
end

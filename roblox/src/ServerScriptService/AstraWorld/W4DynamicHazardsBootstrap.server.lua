local DynamicHazardService = require(script.Parent.DynamicHazardService)

task.defer(function()
    local ok, err = pcall(DynamicHazardService.Start)
    if not ok then
        warn("[AstraLife][W4] failed to start dynamic hazards: " .. tostring(err))
    end
end)

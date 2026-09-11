local LivingResourceService = require(script.Parent.LivingResourceService)

local result = LivingResourceService.Start()

if result and result.passed then
    print("[AstraLife][W3] Living resources ready")
else
    warn("[AstraLife][W3] Living resource verifier failed")
end

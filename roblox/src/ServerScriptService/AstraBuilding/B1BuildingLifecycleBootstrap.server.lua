local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingLifecycleService = require(script.Parent.BuildingLifecycleService)
local BuildingModules = ReplicatedStorage:WaitForChild("Astra"):WaitForChild("Building")
local B1HardeningVerifier = require(BuildingModules.B1HardeningVerifier)

local result = BuildingLifecycleService.Start()
local hardPassed, hardChecks, hardStats = B1HardeningVerifier.Run()

result.state:SetAttribute("B1HardeningStatus", hardPassed and "PASS" or "FAIL")
for name, value in pairs(hardChecks) do
    result.state:SetAttribute("B1HardeningCheck_" .. name, value)
end
result.state:SetAttribute("B1HardeningRemovedCalls", hardStats.removedCalls)
result.state:SetAttribute("B1HardeningDepositAttempts", hardStats.depositAttempts)
result.state:SetAttribute("B1HardeningPendingRefunds", hardStats.pendingRefunds)

if not hardPassed then
    result.state:SetAttribute("B1Status", "FAIL")
end

print(string.format(
    "[AstraLife][B1] lifecycle=%s hardening=%s",
    tostring(result.state:GetAttribute("B1Status")),
    tostring(result.state:GetAttribute("B1HardeningStatus"))
))

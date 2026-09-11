local K16Verifier = {}

local function captureStocks(sourceReader)
    local s = sourceReader.ReadStocks()
    return string.format("%s|%s|%s|%s|%s", s.Wood, s.Stone, s.Food, s.Water, s.Total)
end

local function captureAgents(sourceReader)
    local agents = sourceReader.Agents()
    local out = {}
    if agents then
        for _, agent in ipairs(agents:GetChildren()) do
            if agent:IsA("Model") then
                local root = agent:FindFirstChild("HumanoidRootPart")
                local p = root and root.Position or Vector3.zero
                table.insert(out, string.format("%s:%s:%.3f:%.3f:%.3f", agent.Name, tostring(agent:GetAttribute("Role")), p.X, p.Y, p.Z))
            end
        end
    end
    table.sort(out)
    return table.concat(out, "|")
end

function K16Verifier.Capture(sourceReader)
    return { stocks = captureStocks(sourceReader), agents = captureAgents(sourceReader) }
end

function K16Verifier.Verify(scope, before, after)
    local ok = before.stocks == after.stocks and before.agents == after.agents
    local count = scope:GetAttribute("PlanCount") or 0
    ok = ok and type(count) == "number" and count >= 0
    scope:SetAttribute("K16Status", ok and "PASS" or "ERROR")
    return ok
end

return K16Verifier

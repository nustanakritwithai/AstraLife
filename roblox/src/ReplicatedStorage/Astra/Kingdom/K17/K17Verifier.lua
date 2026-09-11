local K17Verifier = {}

local function stockSig(reader)
    local s = reader.ReadStocks()
    return string.format("%s|%s|%s|%s|%s", s.Wood, s.Stone, s.Food, s.Water, s.Total)
end

local function agentSig(reader)
    local agents = reader.Agents()
    local rows = {}
    if agents then
        for _, agent in ipairs(agents:GetChildren()) do
            if agent:IsA("Model") then
                table.insert(rows, agent.Name .. ":" .. tostring(agent:GetAttribute("Role")))
            end
        end
    end
    table.sort(rows)
    return table.concat(rows, "|")
end

function K17Verifier.Capture(reader)
    return { stocks = stockSig(reader), agents = agentSig(reader) }
end

function K17Verifier.Verify(scope, before, after)
    local ok = before.stocks == after.stocks and before.agents == after.agents
    local readiness = scope:GetAttribute("Readiness")
    ok = ok and type(readiness) == "number" and readiness >= 0 and readiness <= 100
    scope:SetAttribute("K17Status", ok and "PASS" or "ERROR")
    return ok
end

return K17Verifier

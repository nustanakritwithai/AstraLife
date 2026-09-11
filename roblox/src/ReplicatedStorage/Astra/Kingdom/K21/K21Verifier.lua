local K21Verifier = {}

local function capture(reader)
    local s = reader.ReadStocks()
    local rows = { string.format("%s|%s|%s|%s|%s", s.Wood, s.Stone, s.Food, s.Water, s.Total) }
    local agents = reader.Agents()
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

function K21Verifier.Capture(reader)
    return capture(reader)
end

function K21Verifier.Verify(scope, before, after)
    local ok = before == after
    local queued = scope:GetAttribute("QueuedEventCount") or 0
    ok = ok and type(queued) == "number" and queued >= 0 and queued <= 256
    scope:SetAttribute("K21Status", ok and "PASS" or "ERROR")
    return ok
end

return K21Verifier

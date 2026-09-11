local K20Verifier = {}

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

function K20Verifier.Capture(reader)
    return capture(reader)
end

function K20Verifier.Verify(scope, before, after)
    local ok = before == after
    local count = scope:GetAttribute("EventCount") or 0
    ok = ok and type(count) == "number" and count >= 0 and count <= 256
    scope:SetAttribute("K20Status", ok and "PASS" or "ERROR")
    return ok
end

return K20Verifier

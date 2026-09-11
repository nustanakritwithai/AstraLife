local K19Verifier = {}

local function capture(reader)
    local s = reader.ReadStocks()
    local agents = reader.Agents()
    local rows = { string.format("%s|%s|%s|%s|%s", s.Wood, s.Stone, s.Food, s.Water, s.Total) }
    if agents then
        for _, agent in ipairs(agents:GetChildren()) do
            if agent:IsA("Model") then
                table.insert(rows, table.concat({
                    agent.Name,
                    tostring(agent:GetAttribute("Role")),
                    tostring(agent:GetAttribute("Hunger")),
                    tostring(agent:GetAttribute("Thirst")),
                    tostring(agent:GetAttribute("Safety")),
                    tostring(agent:GetAttribute("Social")),
                }, ":"))
            end
        end
    end
    table.sort(rows)
    return table.concat(rows, "|")
end

function K19Verifier.Capture(reader)
    return capture(reader)
end

function K19Verifier.Verify(scope, before, after)
    local ok = before == after
    for _, key in ipairs({ "PublicSupport", "PublicFear", "PublicGrievance", "PublicLoyalty" }) do
        local value = scope:GetAttribute(key)
        ok = ok and type(value) == "number" and value >= 0 and value <= 100
    end
    scope:SetAttribute("K19Status", ok and "PASS" or "ERROR")
    return ok
end

return K19Verifier

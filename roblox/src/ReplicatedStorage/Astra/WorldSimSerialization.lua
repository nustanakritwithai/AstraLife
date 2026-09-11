local WorldSimSerialization = {}

local function encodeValue(value)
    local t = typeof(value)
    if t == "Vector3" then
        return string.format("v3(%.3f,%.3f,%.3f)", value.X, value.Y, value.Z)
    elseif t == "number" then
        return string.format("n(%.6f)", value)
    elseif t == "boolean" then
        return value and "b(1)" or "b(0)"
    end
    return "s(" .. tostring(value):gsub("[|;=]", "_") .. ")"
end

local function appendMap(parts, prefix, map)
    local keys = {}
    for key in pairs(map or {}) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        table.insert(parts, prefix .. tostring(key) .. "=" .. encodeValue(map[key]))
    end
end

function WorldSimSerialization.Serialize(snapshot)
    local parts = { "tick=" .. tostring(snapshot.tick or 0), "fp=" .. tostring(snapshot.fingerprint or "") }
    appendMap(parts, "world.", snapshot.world or {})

    for _, agent in ipairs(snapshot.agents or {}) do
        table.insert(parts, "agent=" .. tostring(agent.id))
        table.insert(parts, "agent.cell=" .. tostring(agent.cell))
        if agent.position then table.insert(parts, "agent.position=" .. encodeValue(agent.position)) end
        if agent.health ~= nil then table.insert(parts, "agent.health=" .. encodeValue(agent.health)) end
        appendMap(parts, "agent.attr.", agent.attributes or {})
    end

    for _, resource in ipairs(snapshot.resources or {}) do
        table.insert(parts, table.concat({
            "resource", tostring(resource.id), tostring(resource.resourceType), tostring(resource.active), tostring(resource.amount), tostring(resource.cell),
        }, ":"))
    end

    for _, structure in ipairs(snapshot.structures or {}) do
        table.insert(parts, "structure:" .. tostring(structure.id) .. ":" .. tostring(structure.cell))
    end

    return table.concat(parts, "|")
end

return WorldSimSerialization

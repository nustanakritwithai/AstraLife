local S5Verifier = {}

function S5Verifier.Verify(graph, scope)
    local errors, count = {}, 0
    for id, recipe in pairs(graph.All()) do
        count += 1
        if type(id) ~= "string" or id == "" then table.insert(errors, "invalid_id") end
        if type(recipe.station) ~= "string" or recipe.station == "" then table.insert(errors, "station:" .. tostring(id)) end
        if type(recipe.craftTicks) ~= "number" or recipe.craftTicks <= 0 then table.insert(errors, "ticks:" .. tostring(id)) end
        if type(recipe.researchTier) ~= "number" or recipe.researchTier < 0 then table.insert(errors, "research:" .. tostring(id)) end
        local inputCount, outputCount = 0, 0
        for itemId, amount in pairs(recipe.inputs or {}) do
            inputCount += 1
            if type(itemId) ~= "string" or type(amount) ~= "number" or amount <= 0 then table.insert(errors, "input:" .. tostring(id)) end
        end
        for itemId, amount in pairs(recipe.outputs or {}) do
            outputCount += 1
            if type(itemId) ~= "string" or type(amount) ~= "number" or amount <= 0 then table.insert(errors, "output:" .. tostring(id)) end
        end
        if inputCount == 0 or outputCount == 0 then table.insert(errors, "empty_recipe:" .. tostring(id)) end
    end
    local status = (#errors == 0 and count > 0) and "PASS" or "ERROR"
    scope:SetAttribute("S5Status", status)
    scope:SetAttribute("RecipeCount", count)
    scope:SetAttribute("S5Errors", table.concat(errors, ","))
    return status, errors
end
return S5Verifier

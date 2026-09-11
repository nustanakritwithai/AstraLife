local Organization = {}

function Organization.Update(folders, settlementFolder, organizationFolder)
    local members = 0
    local roleCounts = {}
    for _, agent in ipairs(folders.agents:GetChildren()) do
        if agent:IsA("Model") then
            members += 1
            local role = agent:GetAttribute("Role") or "Unknown"
            roleCounts[role] = (roleCounts[role] or 0) + 1
        end
    end

    local state = folders.state
    local wealth = state:GetAttribute("StockTotal") or 0
    local food = state:GetAttribute("Stock_Food") or 0
    local water = state:GetAttribute("Stock_Water") or 0
    local stability = settlementFolder:GetAttribute("Stability") or 50
    local reputation = math.max(0, math.min(100, 35 + stability * 0.45 + math.min(wealth, 40) * 0.5))

    organizationFolder:SetAttribute("OrganizationId", "astra-colony")
    organizationFolder:SetAttribute("Purpose", "survive_build_expand")
    organizationFolder:SetAttribute("Status", "active")
    organizationFolder:SetAttribute("MemberCount", members)
    organizationFolder:SetAttribute("Wealth", wealth)
    organizationFolder:SetAttribute("FoodReserve", food)
    organizationFolder:SetAttribute("WaterReserve", water)
    organizationFolder:SetAttribute("Reputation", math.floor(reputation * 10 + 0.5) / 10)
    for role, count in pairs(roleCounts) do
        organizationFolder:SetAttribute("Role_" .. role, count)
    end

    return { memberCount = members, wealth = wealth, reputation = reputation, roles = roleCounts }
end

return Organization

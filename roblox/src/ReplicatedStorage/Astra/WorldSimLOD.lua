local Players = game:GetService("Players")

local WorldSimLOD = {}

local function nearestPlayerDistance(position)
    local nearest = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            nearest = math.min(nearest, (position - root.Position).Magnitude)
        end
    end
    return nearest
end

function WorldSimLOD.UpdateAgent(agent)
    local root = agent:FindFirstChild("HumanoidRootPart")
    if not root then return "Unknown", math.huge end
    local distance = nearestPlayerDistance(root.Position)
    local lod
    if distance <= 120 then
        lod = "A_Full"
    elseif distance <= 300 then
        lod = "B_Reduced"
    else
        lod = "C_Abstract"
    end
    agent:SetAttribute("SimulationLOD", lod)
    agent:SetAttribute("NearestPlayerDistance", distance == math.huge and -1 or math.floor(distance * 10 + 0.5) / 10)
    return lod, distance
end

function WorldSimLOD.UpdateAll(agentsFolder, metricsFolder)
    local counts = { A_Full = 0, B_Reduced = 0, C_Abstract = 0, Unknown = 0 }
    for _, agent in ipairs(agentsFolder:GetChildren()) do
        if agent:IsA("Model") then
            local lod = WorldSimLOD.UpdateAgent(agent)
            counts[lod] = (counts[lod] or 0) + 1
        end
    end
    if metricsFolder then
        metricsFolder:SetAttribute("LOD_A_Full", counts.A_Full)
        metricsFolder:SetAttribute("LOD_B_Reduced", counts.B_Reduced)
        metricsFolder:SetAttribute("LOD_C_Abstract", counts.C_Abstract)
    end
    return counts
end

return WorldSimLOD

local Players = game:GetService("Players")

local Perception = {}

local function sortByDistance(list)
    table.sort(list, function(a, b)
        return a.distance < b.distance
    end)
end

function Perception.Observe(agent, folders, config)
    local root = agent:FindFirstChild("HumanoidRootPart")
    if not root then
        return {
            resources = {},
            agents = {},
            threats = {},
            players = {},
        }
    end

    local observations = {
        resources = {},
        agents = {},
        threats = {},
        players = {},
    }

    for _, resource in ipairs(folders.resources:GetChildren()) do
        if resource:IsA("BasePart") and resource:GetAttribute("Active") ~= false then
            local distance = (resource.Position - root.Position).Magnitude
            if distance <= config.ResourceRange then
                table.insert(observations.resources, {
                    instance = resource,
                    position = resource.Position,
                    distance = distance,
                })
            end
        end
    end

    for _, other in ipairs(folders.agents:GetChildren()) do
        if other ~= agent and other:IsA("Model") then
            local otherRoot = other:FindFirstChild("HumanoidRootPart")
            local otherHumanoid = other:FindFirstChildOfClass("Humanoid")
            if otherRoot and otherHumanoid and otherHumanoid.Health > 0 then
                local distance = (otherRoot.Position - root.Position).Magnitude
                if distance <= config.AgentRange then
                    table.insert(observations.agents, {
                        instance = other,
                        position = otherRoot.Position,
                        distance = distance,
                    })
                end
            end
        end
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= agent and obj:GetAttribute("IsThreat") == true then
            local threatRoot = obj:FindFirstChild("HumanoidRootPart")
            local threatHumanoid = obj:FindFirstChildOfClass("Humanoid")
            if threatRoot and threatHumanoid and threatHumanoid.Health > 0 then
                local distance = (threatRoot.Position - root.Position).Magnitude
                if distance <= config.ThreatRange then
                    table.insert(observations.threats, {
                        instance = obj,
                        position = threatRoot.Position,
                        distance = distance,
                    })
                end
            end
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local playerRoot = character:FindFirstChild("HumanoidRootPart")
            local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
            if playerRoot and playerHumanoid and playerHumanoid.Health > 0 then
                local distance = (playerRoot.Position - root.Position).Magnitude
                if distance <= config.PerceptionRange then
                    table.insert(observations.players, {
                        player = player,
                        character = character,
                        position = playerRoot.Position,
                        distance = distance,
                    })
                end
            end
        end
    end

    sortByDistance(observations.resources)
    sortByDistance(observations.agents)
    sortByDistance(observations.threats)
    sortByDistance(observations.players)

    return observations
end

return Perception

local WorldSimRouteSecurity = {}

local TERRAIN_RISK = {
    plain = 0.10,
    forest = 0.32,
    hill = 0.18,
    river = 0.22,
    road = 0.06,
    marsh = 0.28,
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function WorldSimRouteSecurity.Update(routesFolder, threatsFolder, terrainFolder, settlementFolder, securityFolder)
    local threatPressure = threatsFolder:GetAttribute("ThreatPressure") or 0
    local dominantTerrain = terrainFolder:GetAttribute("DominantTerrain") or "plain"
    local terrainRisk = TERRAIN_RISK[dominantTerrain] or TERRAIN_RISK.plain
    local averageDistance = routesFolder:GetAttribute("AverageEdgeDistance") or 0
    local routeCount = routesFolder:GetAttribute("EdgeCount") or 0
    local stability = (settlementFolder:GetAttribute("Stability") or 50) / 100
    local prosperity = (settlementFolder:GetAttribute("Prosperity") or 50) / 100

    local distanceRisk = clamp(averageDistance / 180, 0, 0.45)
    local patrolCapacity = clamp(stability * 0.45 + prosperity * 0.25 + math.min(routeCount, 12) / 12 * 0.12, 0, 1)
    local ambushRisk = clamp(threatPressure * 0.48 + terrainRisk + distanceRisk * 0.25 - patrolCapacity * 0.28, 0.02, 0.85)
    local securityPressure = clamp(ambushRisk * 0.7 + threatPressure * 0.3, 0, 1)

    securityFolder:SetAttribute("DominantTerrain", dominantTerrain)
    securityFolder:SetAttribute("TerrainRisk", math.floor(terrainRisk * 1000 + 0.5) / 1000)
    securityFolder:SetAttribute("AverageRouteDistance", math.floor(averageDistance * 10 + 0.5) / 10)
    securityFolder:SetAttribute("PatrolCapacity", math.floor(patrolCapacity * 1000 + 0.5) / 10)
    securityFolder:SetAttribute("AmbushRisk", math.floor(ambushRisk * 1000 + 0.5) / 10)
    securityFolder:SetAttribute("SecurityPressure", math.floor(securityPressure * 1000 + 0.5) / 10)
    securityFolder:SetAttribute("SecurityState", securityPressure >= 0.7 and "Critical" or securityPressure >= 0.45 and "Unsafe" or securityPressure >= 0.25 and "Watch" or "Secure")

    return {
        ambushRisk = ambushRisk,
        securityPressure = securityPressure,
        patrolCapacity = patrolCapacity,
    }
end

return WorldSimRouteSecurity

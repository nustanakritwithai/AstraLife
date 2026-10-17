-- I5: map SurvivalCrafting S1 crafted build_part items onto B1 piece + material grade.
-- S9 is item/policy only when present; here S1 catalog items are the available surface.
-- Gaps are documented in MappingGaps() — no invented piece types.

local CraftedBuildPartMapping = {}

local MAPPING = {
	WoodFoundation = { pieceType = "FoundationSquare", materialGrade = "Wood" },
	WoodWall = { pieceType = "Wall", materialGrade = "Wood" },
	WoodDoorFrame = { pieceType = "DoorFrame", materialGrade = "Wood" },
	WoodRoof = { pieceType = "Roof", materialGrade = "Wood" },
	StoneFoundation = { pieceType = "FoundationSquare", materialGrade = "Stone" },
	StoneWall = { pieceType = "Wall", materialGrade = "Stone" },
	MetalWall = { pieceType = "Wall", materialGrade = "Metal" },
}

-- Documented gaps: B piece types / grades with no matching crafted S1 item yet,
-- and S concepts not composed (S9 catalog absent on this branch).
local GAPS = {
	"S9 building catalog not present on integration branch — mapped S1 build_part items only",
	"No crafted item for FoundationTriangle / FloorSquare / HalfWall / Stairs / WindowFrame",
	"No crafted Scaffold-grade starter kit item",
	"No crafted StoneRoof / MetalFoundation / MetalDoorFrame equivalents yet",
}

function CraftedBuildPartMapping.Get(itemId)
	return MAPPING[itemId]
end

function CraftedBuildPartMapping.All()
	local copy = {}
	for itemId, entry in pairs(MAPPING) do
		copy[itemId] = {
			pieceType = entry.pieceType,
			materialGrade = entry.materialGrade,
		}
	end
	return copy
end

function CraftedBuildPartMapping.MappingGaps()
	local gaps = {}
	for _, gap in ipairs(GAPS) do
		table.insert(gaps, gap)
	end
	return gaps
end

function CraftedBuildPartMapping.Count()
	local n = 0
	for _ in pairs(MAPPING) do
		n += 1
	end
	return n
end

return CraftedBuildPartMapping

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local InventoryV2 = require(SurvivalCrafting.S4.InventoryV2)
local S4Verifier = require(SurvivalCrafting.S4.S4Verifier)

local scope = StateWriter.Scope("S4InventoryV2")
scope:SetAttribute("Version", "S4-1")
scope:SetAttribute("OwnsLegacyInventory", false)
scope:SetAttribute("InventoryMode", "standalone-container-library")
scope:SetAttribute("SupportsMetadata", true)
scope:SetAttribute("SupportsDurability", true)
scope:SetAttribute("SupportsIdempotentTransactions", true)
S4Verifier.Verify(InventoryV2, scope)

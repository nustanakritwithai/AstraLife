local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local ItemCatalog = require(SurvivalCrafting.S1.ItemCatalog)
local S1Verifier = require(SurvivalCrafting.S1.S1Verifier)

local scope = StateWriter.Scope("S1Items")
scope:SetAttribute("Version", "S1-1")
scope:SetAttribute("OwnsInventory", false)
scope:SetAttribute("OwnsWorldResources", false)
scope:SetAttribute("CatalogMode", "data-contract")
S1Verifier.Verify(ItemCatalog, scope)

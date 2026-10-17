local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local RecipeGraph = require(SurvivalCrafting.S5.RecipeGraph)
local S5Verifier = require(SurvivalCrafting.S5.S5Verifier)

local scope = StateWriter.Scope("S5RecipeGraph")
scope:SetAttribute("Version", "S5-1")
scope:SetAttribute("OwnsInventoryTransactions", false)
scope:SetAttribute("OwnsCraftQueue", false)
scope:SetAttribute("RecipeMode", "data-graph")
S5Verifier.Verify(RecipeGraph, scope)

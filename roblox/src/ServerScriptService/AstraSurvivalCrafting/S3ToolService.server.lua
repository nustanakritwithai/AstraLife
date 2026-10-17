local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local ToolCatalog = require(SurvivalCrafting.S3.ToolCatalog)
local S3Verifier = require(SurvivalCrafting.S3.S3Verifier)

local scope = StateWriter.Scope("S3Tools")
scope:SetAttribute("Version", "S3-1")
scope:SetAttribute("OwnsEquippedTools", false)
scope:SetAttribute("OwnsDurabilityMutation", false)
scope:SetAttribute("ToolMode", "data-contract")
S3Verifier.Verify(ToolCatalog, scope)

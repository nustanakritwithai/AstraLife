local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalCrafting = ReplicatedStorage.Astra.SurvivalCrafting
local StateWriter = require(SurvivalCrafting.Core.StateWriter)
local GatheringContracts = require(SurvivalCrafting.S2.GatheringContracts)
local S2Verifier = require(SurvivalCrafting.S2.S2Verifier)

local scope = StateWriter.Scope("S2Gathering")
scope:SetAttribute("Version", "S2-1")
scope:SetAttribute("OwnsWorldResources", false)
scope:SetAttribute("OwnsHarvestTransactions", false)
scope:SetAttribute("ContractMode", "read-only-policy")
S2Verifier.Verify(GatheringContracts, scope)

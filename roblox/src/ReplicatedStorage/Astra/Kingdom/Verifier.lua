local Verifier = {}

local REQUIRED = {
    Market = { "Price_Food", "TradeHealth" },
    Labor = { "HighestDemandProfession", "HighestWagePremium" },
    Settlement = { "Prosperity", "Stability", "Unrest" },
    Organization = { "MemberCount", "Wealth", "Reputation" },
    Governance = { "Legitimacy", "Decision" },
    Recruitment = { "HighestNeedRole", "RecruitmentUrgency" },
    Migration = { "AveragePressure", "SuggestedPolicy" },
}

function Verifier.Update(root, worldState)
    local failures = {}
    for folderName, attributes in pairs(REQUIRED) do
        local folder = root:FindFirstChild(folderName)
        if not folder then
            table.insert(failures, "folder:" .. folderName)
        else
            for _, attribute in ipairs(attributes) do
                if folder:GetAttribute(attribute) == nil then
                    table.insert(failures, folderName .. ":" .. attribute)
                end
            end
        end
    end

    local status = #failures == 0 and "PASS" or "RUNNING"
    root:SetAttribute("VerifierStatus", status)
    root:SetAttribute("VerifierFailures", table.concat(failures, ","))
    worldState:SetAttribute("KingdomAdapterStatus", status)
    return status == "PASS", failures
end

return Verifier

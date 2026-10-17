local Rules = {}

Rules.Coins = { Win = 30, Loss = 10, Draw = 15 }
Rules.MaxStoredClaims = 100

function Rules.CoinsForOutcome(outcome)
    if type(outcome) ~= "string" then return nil end
    return Rules.Coins[outcome]
end

function Rules.IsValidClaimId(claimId)
    return type(claimId) == "string" and #claimId >= 8 and #claimId <= 96 and claimId:match("^[%w_%-:]+$") ~= nil
end

return Rules

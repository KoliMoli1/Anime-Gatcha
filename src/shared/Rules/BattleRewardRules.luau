--!strict
-- Gems for finishing a battle. Claim ids make each reward one-time only.

local Rules = {}

Rules.Gems = { Win = 30, Loss = 10, Draw = 15 } :: { [string]: number }
Rules.MaxStoredClaims = 100

function Rules.gemsForOutcome(outcome: string): number?
	return Rules.Gems[outcome]
end

function Rules.isValidClaimId(claimId: any): boolean
	return type(claimId) == "string" and #claimId >= 8 and #claimId <= 96 and claimId:match("^[%w_%-:]+$") ~= nil
end

return Rules

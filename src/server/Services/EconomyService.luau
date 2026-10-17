--!nonstrict
-- Every currency change goes through here so it is validated and logged.
-- Phase 5 adds receipts (Developer Products) and AnalyticsService economy events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleRewardRules = require(ReplicatedStorage.Shared.Rules.BattleRewardRules)
local ProfileService = require(script.Parent.ProfileService)

local EconomyService = {}

local function log(player: Player, currency: string, amount: number, reason: string)
	print(`[Economy] {player.Name} {currency} {if amount >= 0 then "+" else ""}{amount} ({reason})`)
end

-- Earned gems (never paid gems: those only come from receipts).
function EconomyService.GrantGems(player: Player, amount: number, reason: string): boolean
	if type(amount) ~= "number" or amount <= 0 or amount % 1 ~= 0 then
		return false
	end
	local ok = ProfileService.Update(player, function(data)
		data.Gems.Earned += amount
		return true
	end)
	if ok then
		log(player, "Gems", amount, reason)
	end
	return ok == true
end

-- One-time battle reward keyed by claimId. Returns false if already claimed.
function EconomyService.ClaimReward(player: Player, claimId: string, amount: number?, reason: string): boolean
	if not amount or not BattleRewardRules.isValidClaimId(claimId) then
		return false
	end
	local ok = ProfileService.Update(player, function(data)
		if data.RewardClaims[claimId] then
			return false
		end
		data.RewardClaims[claimId] = os.time()
		data.Gems.Earned += amount
		if reason == "Win" then
			data.Record.Wins += 1
		elseif reason == "Loss" then
			data.Record.Losses += 1
		else
			data.Record.Draws += 1
		end
		return true
	end)
	if ok then
		log(player, "Gems", amount, `battle {reason} {claimId}`)
	end
	return ok == true
end

return EconomyService

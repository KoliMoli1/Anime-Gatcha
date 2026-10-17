--!nonstrict
-- Interim summon kept so the prototype roll button works. Rolls happen on the
-- server only. Phase 5 replaces this with banners, odds display and pity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Content.Characters)
local GachaRules = require(Shared.Rules.GachaRules)
local Schema = require(Shared.Rules.ProfileSchema)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)

local GachaService = {}

local rng = Random.new()
local lastRollAt: { [Player]: number } = {}

local function roll(player: Player)
	local now = os.clock()
	local wait = GachaRules.RollCooldown - (now - (lastRollAt[player] or -math.huge))
	if wait > 0 then
		local data = ProfileService.Get(player)
		return {
			success = false,
			message = "Please wait before rolling again.",
			coins = data and Schema.totalGems(data),
			cost = GachaRules.RollCost,
		}
	end
	lastRollAt[player] = now
	local _, result = ProfileService.Update(player, function(data)
		if not Schema.spendGems(data, GachaRules.RollCost) then
			return false,
				{
					success = false,
					message = "Not enough gems!",
					coins = Schema.totalGems(data),
					cost = GachaRules.RollCost,
				}
		end
		local value = rng:NextInteger(1, 1000)
		local characterId = GachaRules.characterForRoll(value)
		local def = Characters[characterId]
		local outcome, coins = Schema.grantCharacter(data, def, os.time())
		return true,
			{
				success = true,
				value = value,
				characterId = characterId,
				characterName = def.Name,
				outcome = outcome,
				duplicate = outcome ~= "New",
				collectionAdded = outcome == "New",
				cosmeticCoins = coins,
				coins = Schema.totalGems(data),
				cost = GachaRules.RollCost,
			}
	end)
	if type(result) ~= "table" then
		return { success = false, message = "Your profile is still loading." }
	end
	return result
end

function GachaService.Start()
	Net.handle("Roll", { Rate = 2, Burst = 2 }, roll)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRollAt[player] = nil
	end)
end

return GachaService

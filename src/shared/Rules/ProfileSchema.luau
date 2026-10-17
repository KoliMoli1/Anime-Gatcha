--!strict
-- Player save schema v3 (roadmap Phase 0). Pure functions so Lune can test them.
-- v2 = the prototype's DataStore "AnimeGachaPlayerProfiles_v1" ({Coins, OwnedCharacters, SelectedTeam, RewardClaims}).

local Types = require("../Types")
local Loadout = require("./Loadout")
local BattleRewardRules = require("./BattleRewardRules")

local Schema = {}

Schema.VERSION = 3
Schema.STARTING_GEMS = 1000
Schema.STARTER_TEAM = { "TrainingAttack", "TrainingDefense", "TrainingSupport" }

export type CharacterEntry = { Dupes: number, ObtainedAt: number }
export type ItemEntry = { ObtainedAt: number }

export type Data = {
	Version: number,
	Gems: { Paid: number, Earned: number },
	CosmeticCoins: number,
	Shards: number,
	Characters: { [string]: CharacterEntry },
	Items: { [string]: ItemEntry },
	Team: { Types.TeamSlot },
	Pity: { [string]: number },
	Rank: { Season: number, Rank: number, Points: number },
	Record: { Wins: number, Losses: number, Draws: number },
	Quests: { [string]: any },
	Pass: { [string]: any },
	Purchases: { [string]: number },
	RewardClaims: { [string]: number },
	MigratedFromV2: boolean,
}

local function starterTeam(): { Types.TeamSlot }
	local team = {}
	for index, id in Schema.STARTER_TEAM do
		team[index] = { Id = id, Items = {} }
	end
	return team
end

function Schema.default(now: number, characters: { [string]: Types.CharacterDef }?): Data
	local owned = {}
	if characters then
		for id, def in characters do
			if def.Starter then
				owned[id] = { Dupes = 0, ObtainedAt = now }
			end
		end
	end
	return {
		Version = Schema.VERSION,
		Gems = { Paid = 0, Earned = Schema.STARTING_GEMS },
		CosmeticCoins = 0,
		Shards = 0,
		Characters = owned,
		Items = {},
		Team = starterTeam(),
		Pity = {},
		Rank = { Season = 0, Rank = 1, Points = 0 },
		Record = { Wins = 0, Losses = 0, Draws = 0 },
		Quests = {},
		Pass = {},
		Purchases = {},
		RewardClaims = {},
		MigratedFromV2 = false,
	}
end

local function nonNegativeInt(value: any, fallback: number): number
	if type(value) == "number" and value == value and value >= 0 and value < 2 ^ 52 then
		return math.floor(value)
	end
	return fallback
end

-- Copies what is still meaningful from a prototype (v2) save into v3 data.
function Schema.mergeV2(data: Data, raw: any, now: number, characters: { [string]: Types.CharacterDef })
	if type(raw) ~= "table" then
		return
	end
	data.Gems.Earned = nonNegativeInt(raw.Coins, data.Gems.Earned)
	if type(raw.OwnedCharacters) == "table" then
		for id, entry in raw.OwnedCharacters do
			if type(id) == "string" and characters[id] and type(entry) == "table" then
				local obtained = nonNegativeInt(entry.FirstObtainedAt, now)
				local existing = data.Characters[id]
				data.Characters[id] = { Dupes = if existing then existing.Dupes else 0, ObtainedAt = obtained }
			end
		end
	end
	if type(raw.SelectedTeam) == "table" then
		local team = {}
		for index = 1, 3 do
			local id = raw.SelectedTeam[index]
			if type(id) == "string" and data.Characters[id] then
				team[index] = { Id = id, Items = {} }
			end
		end
		if #team == 3 then
			data.Team = team
		end
	end
	if type(raw.RewardClaims) == "table" then
		for claimId, claimedAt in raw.RewardClaims do
			if BattleRewardRules.isValidClaimId(claimId) and type(claimedAt) == "number" then
				data.RewardClaims[claimId] = claimedAt
			end
		end
	end
end

-- Repairs loaded data in place: drops unknown content, restores starters, fixes the team.
function Schema.sanitize(
	data: Data,
	now: number,
	characters: { [string]: Types.CharacterDef },
	items: { [string]: Types.ItemDef }
): Data
	data.Version = Schema.VERSION
	data.Gems.Paid = nonNegativeInt(data.Gems.Paid, 0)
	data.Gems.Earned = nonNegativeInt(data.Gems.Earned, 0)
	data.CosmeticCoins = nonNegativeInt(data.CosmeticCoins, 0)
	data.Shards = nonNegativeInt(data.Shards, 0)

	for id, entry in data.Characters do
		if not characters[id] or type(entry) ~= "table" then
			data.Characters[id] = nil
		else
			entry.Dupes = math.clamp(nonNegativeInt(entry.Dupes, 0), 0, Loadout.MAX_DUPES)
			entry.ObtainedAt = nonNegativeInt(entry.ObtainedAt, now)
		end
	end
	for id, def in characters do
		if def.Starter and not data.Characters[id] then
			data.Characters[id] = { Dupes = 0, ObtainedAt = now }
		end
	end
	for id in data.Items do
		if not items[id] then
			data.Items[id] = nil
		end
	end

	local ok = Loadout.validateTeam(data.Team, data.Characters, data.Items, characters, items)
	if not ok then
		-- Keep the characters if possible and drop items; otherwise fall back to starters.
		local stripped = {}
		for index, slot in data.Team do
			stripped[index] = { Id = slot.Id, Items = {} }
		end
		if Loadout.validateTeam(stripped, data.Characters, data.Items, characters, items) then
			data.Team = stripped
		else
			data.Team = starterTeam()
		end
	end

	local claimCount = 0
	local oldestId, oldestAt = nil, math.huge
	for claimId, claimedAt in data.RewardClaims do
		claimCount += 1
		if claimedAt < oldestAt then
			oldestId, oldestAt = claimId, claimedAt
		end
	end
	if claimCount > BattleRewardRules.MaxStoredClaims and oldestId then
		data.RewardClaims[oldestId] = nil
	end
	return data
end

-- Applies a pulled character: new, duplicate (raises capacity) or overflow (Cosmetic Coins).
-- Returns "New" | "Duplicate" | "Overflow" and the coins granted.
function Schema.grantCharacter(data: Data, def: Types.CharacterDef, now: number): (string, number)
	local entry = data.Characters[def.Id]
	if not entry then
		data.Characters[def.Id] = { Dupes = 0, ObtainedAt = now }
		return "New", 0
	end
	if entry.Dupes < Loadout.MAX_DUPES then
		entry.Dupes += 1
		return "Duplicate", 0
	end
	local coins = Loadout.OVERFLOW_COINS[def.Rarity] or 0
	data.CosmeticCoins += coins
	return "Overflow", coins
end

-- Total spendable gems (earned are spent first).
function Schema.totalGems(data: Data): number
	return data.Gems.Earned + data.Gems.Paid
end

function Schema.spendGems(data: Data, amount: number): boolean
	if Schema.totalGems(data) < amount then
		return false
	end
	local fromEarned = math.min(data.Gems.Earned, amount)
	data.Gems.Earned -= fromEarned
	data.Gems.Paid -= amount - fromEarned
	return true
end

return Schema

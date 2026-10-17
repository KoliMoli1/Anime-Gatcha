--!strict
-- Team and equipment rules (roadmap: Character growth).
-- * 3 distinct owned characters per team.
-- * Up to 3 items per unit; total item Value must fit the unit's Equip Capacity.
-- * Each item can be used once per team.
-- * Capacity grows with duplicates, up to MAX_DUPES.

local Types = require("../Types")

local Loadout = {}

Loadout.TEAM_SIZE = 3
Loadout.ITEM_SLOTS = 3
Loadout.MAX_DUPES = 5
Loadout.BASE_CAPACITY = { [5] = 12, [4] = 10, [3] = 8 } :: { [number]: number }
Loadout.CAPACITY_PER_DUPE = { [5] = 4, [4] = 3, [3] = 2 } :: { [number]: number }
-- Cosmetic Coins for a duplicate past MAX_DUPES.
Loadout.OVERFLOW_COINS = { [5] = 25, [4] = 10, [3] = 3 } :: { [number]: number }

function Loadout.itemValue(item: Types.ItemDef): number
	return item.Stars * 2
end

function Loadout.capacity(rarity: number, dupes: number): number
	local base = Loadout.BASE_CAPACITY[rarity] or Loadout.BASE_CAPACITY[3]
	local per = Loadout.CAPACITY_PER_DUPE[rarity] or Loadout.CAPACITY_PER_DUPE[3]
	return base + per * math.clamp(dupes, 0, Loadout.MAX_DUPES)
end

export type OwnedCharacters = { [string]: any }
export type OwnedItems = { [string]: any }

-- Checks a saved team against what the player owns. Returns ok, or false + reason.
function Loadout.validateTeam(
	team: { Types.TeamSlot },
	ownedCharacters: OwnedCharacters,
	ownedItems: OwnedItems,
	characters: { [string]: Types.CharacterDef },
	items: { [string]: Types.ItemDef }
): (boolean, string?)
	if type(team) ~= "table" or #team ~= Loadout.TEAM_SIZE then
		return false, "A team needs exactly 3 characters."
	end
	local seenCharacters: { [string]: boolean } = {}
	local seenItems: { [string]: boolean } = {}
	for index = 1, Loadout.TEAM_SIZE do
		local slot = team[index]
		if type(slot) ~= "table" or type(slot.Id) ~= "string" then
			return false, `Slot {index} is empty.`
		end
		local character = characters[slot.Id]
		if not character then
			return false, `Slot {index} has an unknown character.`
		end
		local owned = ownedCharacters[slot.Id]
		if not owned then
			return false, `You do not own {character.Name}.`
		end
		if seenCharacters[slot.Id] then
			return false, "Each character can only appear once per team."
		end
		seenCharacters[slot.Id] = true

		local slotItems: { string } = slot.Items or {}
		if type(slotItems) ~= "table" or #slotItems > Loadout.ITEM_SLOTS then
			return false, `{character.Name} can hold at most {Loadout.ITEM_SLOTS} items.`
		end
		local used = 0
		for _, itemId in slotItems do
			local item = type(itemId) == "string" and items[itemId] or nil
			if not item then
				return false, `{character.Name} has an unknown item.`
			end
			if not ownedItems[itemId] then
				return false, `You do not own {item.Name}.`
			end
			if seenItems[itemId] then
				return false, `{item.Name} can only be used once per team.`
			end
			seenItems[itemId] = true
			used += Loadout.itemValue(item)
		end
		local cap = Loadout.capacity(character.Rarity, owned.Dupes or 0)
		if used > cap then
			return false, `{character.Name}'s items need {used} capacity but only {cap} is available.`
		end
	end
	return true, nil
end

-- Builds battle loadouts from a validated team.
function Loadout.toBattleTeam(
	team: { Types.TeamSlot },
	characters: { [string]: Types.CharacterDef },
	items: { [string]: Types.ItemDef }
): Types.TeamLoadout
	local result: Types.TeamLoadout = {}
	for index, slot in team do
		local equipped = {}
		local slotItems: { string } = slot.Items or {}
		for _, itemId in slotItems do
			table.insert(equipped, items[itemId])
		end
		result[index] = { Character = characters[slot.Id], Items = equipped }
	end
	return result
end

return Loadout

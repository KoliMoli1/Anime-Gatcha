--!strict
-- Summon rules (roadmap Phase 5). Pure functions so Lune can test every odds and pity rule.
--
-- * One summon costs 100 Gems; a 10-summon costs 1,000.
-- * Featured 5-star rate 0.5%. Soft pity: +3% per summon from the 120th summon since the
--   last 5-star (SinceFive), so the rate climbs fast near the end.
-- * Every summon adds 1 pity point. At 160 points the player earns a selector ticket for any
--   featured 5-star of that banner. Points carry over between banners of the same PityGroup
--   and do not reset when a 5-star drops (deck rule); SinceFive does, which keeps soft pity
--   from handing out a 5-star on every summon after a lucky pull.
-- * At least one 4-star character every 10 summons (SinceFour), for singles and 10-summons alike.

local Banners = require("../Content/Banners")
local Types = require("../Types")
local Rng = require("../Util/Rng")

local Summon = {}

Summon.COST = 100
Summon.MULTI_COUNT = 10
Summon.SOFT_PITY_START = 120
Summon.SOFT_PITY_STEP = 0.03
Summon.SELECTOR_PITY = 160
Summon.FOUR_STAR_EVERY = 10
-- Shards for a duplicate item, by stars.
Summon.ITEM_SHARDS = { [1] = 1, [2] = 3, [3] = 8, [4] = 20, [5] = 50 } :: { [number]: number }

export type PityState = { Points: number, SinceFive: number, SinceFour: number }

export type Tier = "Featured5" | "Featured4" | "Standard4" | "Item3" | "Item2" | "Item1"

export type Result = {
	Kind: "Character" | "Item",
	Id: string,
	Tier: Tier,
	-- Character rarity or item stars.
	Rarity: number,
	-- True when the 4-star guarantee decided this result.
	Guaranteed: boolean?,
}

export type OddsLine = { Tier: Tier, Label: string, Chance: number }

Summon.TIER_ORDER = { "Featured5", "Featured4", "Standard4", "Item3", "Item2", "Item1" } :: { Tier }
Summon.TIER_LABEL = {
	Featured5 = "Featured 5-star character",
	Featured4 = "Featured 4-star character",
	Standard4 = "Standard 4-star character",
	Item3 = "3-star item",
	Item2 = "2-star item",
	Item1 = "1-star item",
} :: { [Tier]: string }
local TIER_RARITY = { Featured5 = 5, Featured4 = 4, Standard4 = 4, Item3 = 3, Item2 = 2, Item1 = 1 }

function Summon.newPity(): PityState
	return { Points = 0, SinceFive = 0, SinceFour = 0 }
end

-- Repairs a saved pity entry (old saves stored a plain number or nothing).
function Summon.sanitizePity(raw: any): PityState
	local state = Summon.newPity()
	if type(raw) == "table" then
		for key in state do
			local value = raw[key]
			if type(value) == "number" and value == value and value >= 0 and value < 1e6 then
				(state :: any)[key] = math.floor(value)
			end
		end
	end
	return state
end

local function itemPool(items: { [string]: Types.ItemDef }, stars: number): { string }
	local pool = {}
	for id, item in items do
		if item.Stars == stars then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	return pool
end

-- Odds for the next summon on this banner with this pity, as fractions totalling 1.
-- Empty pools hand their share down (featured 4-star -> standard 4-star -> 3-star items),
-- so the shown odds always match what can really drop.
function Summon.odds(banner: Banners.Banner, pity: PityState, items: { [string]: Types.ItemDef }): { OddsLine }
	local base = banner.Odds
	local chances: { [Tier]: number } = {
		Featured5 = base.Featured5,
		Featured4 = base.Featured4,
		Standard4 = base.Standard4,
		Item3 = base.Item3,
		Item2 = base.Item2,
		Item1 = base.Item1,
	}
	if #banner.Featured4 == 0 then
		chances.Standard4 += chances.Featured4
		chances.Featured4 = 0
	end
	if #banner.Standard4 == 0 then
		chances.Item3 += chances.Standard4
		chances.Standard4 = 0
	end
	-- Item tiers with no items fall to the next tier down (3 -> 2 -> 1).
	if #itemPool(items, 3) == 0 then
		chances.Item2 += chances.Item3
		chances.Item3 = 0
	end
	if #itemPool(items, 2) == 0 then
		chances.Item1 += chances.Item2
		chances.Item2 = 0
	end

	-- Soft pity raises the 5-star rate and shrinks everything else in proportion.
	local nth = pity.SinceFive + 1
	if nth >= Summon.SOFT_PITY_START then
		local raised = math.min(1, base.Featured5 + Summon.SOFT_PITY_STEP * (nth - Summon.SOFT_PITY_START + 1))
		local rest = 1 - chances.Featured5
		local scale = if rest > 0 then (1 - raised) / rest else 0
		for _, tier in Summon.TIER_ORDER do
			if tier ~= "Featured5" then
				chances[tier] *= scale
			end
		end
		chances.Featured5 = raised
	end

	local lines = {}
	for _, tier in Summon.TIER_ORDER do
		table.insert(lines, { Tier = tier, Label = Summon.TIER_LABEL[tier], Chance = chances[tier] })
	end
	return lines
end

-- True when the next summon is guaranteed to be a 4-star character or better.
function Summon.fourStarDue(pity: PityState): boolean
	return pity.SinceFour + 1 >= Summon.FOUR_STAR_EVERY
end

local function pick(rng: Rng.Rng, list: { string }): string
	return list[rng:integer(1, #list)]
end

local function drawTier(rng: Rng.Rng, lines: { OddsLine }, charactersOnly: boolean): Tier
	local total = 0
	for _, line in lines do
		if not charactersOnly or TIER_RARITY[line.Tier] >= 4 then
			total += line.Chance
		end
	end
	local roll = rng:next() * total
	local last: Tier = "Item1"
	for _, line in lines do
		if line.Chance > 0 and (not charactersOnly or TIER_RARITY[line.Tier] >= 4) then
			last = line.Tier
			roll -= line.Chance
			if roll < 0 then
				return line.Tier
			end
		end
	end
	return last
end

-- One summon. Mutates pity and returns the result plus whether a selector ticket was earned.
function Summon.roll(
	rng: Rng.Rng,
	banner: Banners.Banner,
	pity: PityState,
	items: { [string]: Types.ItemDef }
): (Result, boolean)
	local lines = Summon.odds(banner, pity, items)
	local guaranteed = Summon.fourStarDue(pity)
	local tier = drawTier(rng, lines, guaranteed)
	local result: Result
	if tier == "Featured5" then
		result = { Kind = "Character", Id = pick(rng, banner.Featured5), Tier = tier, Rarity = 5 }
	elseif tier == "Featured4" then
		result = { Kind = "Character", Id = pick(rng, banner.Featured4), Tier = tier, Rarity = 4 }
	elseif tier == "Standard4" then
		result = { Kind = "Character", Id = pick(rng, banner.Standard4), Tier = tier, Rarity = 4 }
	else
		local stars = TIER_RARITY[tier]
		result = { Kind = "Item", Id = pick(rng, itemPool(items, stars)), Tier = tier, Rarity = stars }
	end
	if guaranteed then
		result.Guaranteed = true
	end

	pity.Points += 1
	pity.SinceFive = if result.Rarity == 5 and result.Kind == "Character" then 0 else pity.SinceFive + 1
	pity.SinceFour = if result.Kind == "Character" then 0 else pity.SinceFour + 1
	local ticket = false
	if pity.Points >= Summon.SELECTOR_PITY then
		pity.Points -= Summon.SELECTOR_PITY
		ticket = true
	end
	return result, ticket
end

-- count summons in a row. Returns results and how many selector tickets were earned.
function Summon.many(
	rng: Rng.Rng,
	banner: Banners.Banner,
	pity: PityState,
	items: { [string]: Types.ItemDef },
	count: number
): ({ Result }, number)
	local results, tickets = {}, 0
	for _ = 1, count do
		local result, ticket = Summon.roll(rng, banner, pity, items)
		table.insert(results, result)
		if ticket then
			tickets += 1
		end
	end
	return results, tickets
end

function Summon.cost(count: number): number
	return Summon.COST * count
end

return Summon

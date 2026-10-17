--!strict
-- Stat math. Relative stats (HP/ATK/DEF/SPD) scale by percent; the rest add points.
-- Rules (roadmap Combat spec):
-- * Battle modifiers on one stat are capped at +/-50%.
-- * No stat drops below 50% of its pre-battle value; DEF never below DEF_FLOOR.
-- * Max HP is never lowered by effects.

local Types = require("../Types")

local Stats = {}

Stats.MOD_CAP = 0.5
Stats.MIN_FRACTION = 0.5
Stats.DEF_FLOOR = 20
Stats.DEFENSE_CONSTANT = 100

local RELATIVE: { [string]: boolean } = { HP = true, ATK = true, DEF = true, SPD = true }

function Stats.isRelative(stat: Types.StatName): boolean
	return RELATIVE[stat] == true
end

export type BattleStats = Types.StatBlock & { SpeedMin: number, SpeedMax: number }

-- Pre-battle stats: character base plus equipped items.
function Stats.withItems(character: Types.CharacterDef, items: { Types.ItemDef }): BattleStats
	local base = character.Stats
	local bonus: { [string]: number } = {}
	for _, item in items do
		for stat, amount in item.Bonuses do
			bonus[stat] = (bonus[stat] or 0) + amount
		end
	end
	local function relative(stat: string, value: number): number
		return math.floor(value * (1 + (bonus[stat] or 0)) + 0.5)
	end
	local function additive(stat: string, value: number): number
		return value + (bonus[stat] or 0)
	end
	local speedScale = 1 + (bonus.SPD or 0)
	return {
		HP = relative("HP", base.HP),
		ATK = relative("ATK", base.ATK),
		DEF = relative("DEF", base.DEF),
		CritRate = additive("CritRate", base.CritRate),
		CritDamage = additive("CritDamage", base.CritDamage),
		EFF = additive("EFF", base.EFF),
		RES = additive("RES", base.RES),
		SpeedMin = math.floor(character.Speed.Min * speedScale + 0.5),
		SpeedMax = math.floor(character.Speed.Max * speedScale + 0.5),
	}
end

-- Applies a summed battle modifier to a stat with the cap and global minimum.
function Stats.apply(stat: Types.StatName, base: number, modifier: number): number
	local mod = math.clamp(modifier, -Stats.MOD_CAP, Stats.MOD_CAP)
	local value
	if RELATIVE[stat] then
		value = base * (1 + mod)
	else
		value = base + mod
	end
	value = math.max(value, base * Stats.MIN_FRACTION)
	if stat == "DEF" then
		value = math.max(value, Stats.DEF_FLOOR)
	elseif stat == "CritRate" then
		value = math.clamp(value, 0, 1)
	elseif stat == "CritDamage" then
		value = math.max(value, 1)
	end
	return value
end

-- Damage = ATK x Multiplier x 100 / (100 + max(DEF_FLOOR, DEF)) x crit.
function Stats.damage(attack: number, multiplier: number, defense: number, critMultiplier: number): number
	local mitigation = Stats.DEFENSE_CONSTANT / (Stats.DEFENSE_CONSTANT + math.max(Stats.DEF_FLOOR, defense))
	return math.max(1, math.floor(attack * multiplier * mitigation * critMultiplier + 0.5))
end

-- Net Effectiveness vs Resistance for a debuff landing on a target.
-- Power debuffs scale by (1 + net) within [0.5, 1.5]; duration debuffs gain or lose a turn at +/-0.3.
Stats.DURATION_STEP = 0.3

function Stats.debuffPower(amount: number, effectiveness: number, resistance: number): number
	local scale = math.clamp(1 + (effectiveness - resistance), 0.5, 1.5)
	return amount * scale
end

function Stats.debuffTurns(turns: number, effectiveness: number, resistance: number): number
	local net = effectiveness - resistance
	if net >= Stats.DURATION_STEP then
		return turns + 1
	elseif net <= -Stats.DURATION_STEP then
		return math.max(1, turns - 1)
	end
	return turns
end

return Stats

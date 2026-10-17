--!strict
-- Class stat templates at 5 stars. Solved so an Attack unit's 3.0x skill KOs
-- Defense in ~4 hits, Support ~3, Disrupt/Attack ~2.5, Speed ~1.5 (roadmap Combat spec).
-- 4-star units use FOUR_STAR_SCALE on HP/ATK/DEF and the deck's 4-star speed ranges.

local Types = require("../Types")

export type ClassTemplate = {
	Stats: Types.StatBlock,
	Speed: { [number]: Types.SpeedRange },
	EnergyRegen: number,
}

local Classes = {}

Classes.FOUR_STAR_SCALE = 0.9

Classes.Templates = {
	Defense = {
		Stats = { HP = 645, ATK = 60, DEF = 100, CritRate = 0.05, CritDamage = 1.4, EFF = 0.0, RES = 0.40 },
		Speed = { [5] = { Min = 20, Max = 30 }, [4] = { Min = 15, Max = 25 } },
		EnergyRegen = 1,
	},
	Support = {
		Stats = { HP = 610, ATK = 65, DEF = 60, CritRate = 0.05, CritDamage = 1.4, EFF = 0.10, RES = 0.30 },
		Speed = { [5] = { Min = 35, Max = 45 }, [4] = { Min = 30, Max = 40 } },
		EnergyRegen = 3,
	},
	Disrupt = {
		Stats = { HP = 600, ATK = 95, DEF = 35, CritRate = 0.10, CritDamage = 1.5, EFF = 0.40, RES = 0.10 },
		Speed = { [5] = { Min = 45, Max = 55 }, [4] = { Min = 40, Max = 50 } },
		EnergyRegen = 2,
	},
	Attack = {
		Stats = { HP = 540, ATK = 120, DEF = 40, CritRate = 0.15, CritDamage = 1.6, EFF = 0.05, RES = 0.10 },
		Speed = { [5] = { Min = 55, Max = 70 }, [4] = { Min = 45, Max = 60 } },
		EnergyRegen = 1,
	},
	Speed = {
		Stats = { HP = 390, ATK = 100, DEF = 25, CritRate = 0.30, CritDamage = 1.7, EFF = 0.20, RES = 0.15 },
		Speed = { [5] = { Min = 70, Max = 100 }, [4] = { Min = 60, Max = 80 } },
		EnergyRegen = 2,
	},
} :: { [Types.ClassName]: ClassTemplate }

-- Base stats for a class at a rarity, before any per-character tweaks.
function Classes.statsFor(class: Types.ClassName, rarity: number): Types.StatBlock
	local template = Classes.Templates[class]
	local stats = table.clone(template.Stats)
	if rarity < 5 then
		stats.HP = math.floor(stats.HP * Classes.FOUR_STAR_SCALE + 0.5)
		stats.ATK = math.floor(stats.ATK * Classes.FOUR_STAR_SCALE + 0.5)
		stats.DEF = math.floor(stats.DEF * Classes.FOUR_STAR_SCALE + 0.5)
	end
	return stats
end

function Classes.speedFor(class: Types.ClassName, rarity: number): Types.SpeedRange
	local ranges = Classes.Templates[class].Speed
	return table.clone(ranges[rarity] or ranges[4])
end

return Classes

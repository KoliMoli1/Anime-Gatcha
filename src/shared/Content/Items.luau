--!strict
-- Equipment items. Value = Stars x 2. Budget per Value point: +2% of HP/ATK/DEF/SPD,
-- or +0.01 CritRate/EFF/RES, or +0.02 CritDamage. Stats are fixed: no random upgrades.
-- Placeholder set for Phase 1 balance work; the launch set (40 x 1-3 star,
-- 6 x 4-5 star) arrives in Phase 3.

local Types = require("../Types")

local Items: { [string]: Types.ItemDef } = {
	-- 1 star (Value 2)
	worn_band = { Id = "worn_band", Name = "Worn Band", Stars = 1, Bonuses = { ATK = 0.04 }, Description = "+4% ATK" },
	cloth_wrap = {
		Id = "cloth_wrap",
		Name = "Cloth Wrap",
		Stars = 1,
		Bonuses = { DEF = 0.04 },
		Description = "+4% DEF",
	},
	tin_charm = { Id = "tin_charm", Name = "Tin Charm", Stars = 1, Bonuses = { HP = 0.04 }, Description = "+4% HP" },
	-- 2 stars (Value 4)
	hunter_ring = {
		Id = "hunter_ring",
		Name = "Hunter Ring",
		Stars = 2,
		Bonuses = { CritRate = 0.02, ATK = 0.04 },
		Description = "+2 crit chance, +4% ATK",
	},
	sage_beads = {
		Id = "sage_beads",
		Name = "Sage Beads",
		Stars = 2,
		Bonuses = { EFF = 0.04 },
		Description = "+4 Effectiveness",
	},
	ward_cloak = {
		Id = "ward_cloak",
		Name = "Ward Cloak",
		Stars = 2,
		Bonuses = { RES = 0.04 },
		Description = "+4 Resistance",
	},
	-- 3 stars (Value 6)
	swift_boots = {
		Id = "swift_boots",
		Name = "Swift Boots",
		Stars = 3,
		Bonuses = { SPD = 0.12 },
		Description = "+12% Speed",
	},
	iron_heart = {
		Id = "iron_heart",
		Name = "Iron Heart",
		Stars = 3,
		Bonuses = { HP = 0.06, DEF = 0.06 },
		Description = "+6% HP, +6% DEF",
	},
	-- 4 stars (Value 8)
	duelist_edge = {
		Id = "duelist_edge",
		Name = "Duelist's Edge",
		Stars = 4,
		Bonuses = { ATK = 0.08, CritDamage = 0.08 },
		Description = "+8% ATK, +8 crit damage",
	},
	-- 5 stars (Value 10)
	storm_crown = {
		Id = "storm_crown",
		Name = "Storm Crown",
		Stars = 5,
		Bonuses = { ATK = 0.10, CritRate = 0.05 },
		Description = "+10% ATK, +5 crit chance",
	},
}

return Items

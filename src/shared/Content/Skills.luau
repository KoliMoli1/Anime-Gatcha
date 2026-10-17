--!nonstrict
-- Data file: nonstrict because the old type solver cannot infer literal types in nested effect lists.
-- Skill and passive definitions. Each character lists three skills:
-- [1] Basic (free), [2] Skill, [3] Ultimate. Stat mods on ATK/DEF/SPD are
-- relative (0.2 = +20%); on CritRate/CritDamage/EFF/RES they are additive points.

local Types = require("../Types")

local Skills: { [string]: Types.SkillDef } = {}
local Passives: { [string]: Types.PassiveDef } = {}

local function skill(def: Types.SkillDef)
	Skills[def.Id] = def
end

local function passive(def: Types.PassiveDef)
	Passives[def.Id] = def
end

do
	-- Attack class: big single-target hits, buffs its own damage.
	skill({
		Id = "atk_basic",
		Name = "Strike",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.4,
		Description = "Hit one enemy for 140% ATK.",
	})
	skill({
		Id = "atk_skill",
		Name = "Rising Slash",
		Kind = "Skill",
		Cost = 3,
		Target = "Enemy",
		Multiplier = 3.0,
		Effects = { { Kind = "StatMod", To = "Self", Stat = "ATK", Amount = 0.10, Turns = 2 } },
		Description = "Hit one enemy for 300% ATK, then raise own ATK by 10% for 2 turns.",
	})
	skill({
		Id = "atk_ult",
		Name = "Final Edge",
		Kind = "Ultimate",
		Cost = 5,
		Target = "Enemy",
		Multiplier = 3.2,
		Effects = { { Kind = "StatMod", To = "Self", Stat = "CritRate", Amount = 0.25, Turns = 2 } },
		Description = "Hit one enemy for 320% ATK, then raise own crit chance by 25 points for 2 turns.",
	})

	-- Defense class: taunts, shields, punishes attackers.
	skill({
		Id = "def_basic",
		Name = "Shield Bash",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.3,
		Description = "Hit one enemy for 130% ATK.",
	})
	skill({
		Id = "def_skill",
		Name = "Provoke",
		Kind = "Skill",
		Cost = 2,
		Target = "Self",
		PrioritySpeed = 80,
		Effects = {
			{ Kind = "Taunt", To = "Self", Turns = 1 },
		},
		Description = "Acts at speed 80. Taunt for 1 turn.",
	})
	skill({
		Id = "def_ult",
		Name = "Bulwark",
		Kind = "Ultimate",
		Cost = 4,
		Target = "AllAllies",
		PrioritySpeed = 80,
		Effects = {
			{ Kind = "Shield", To = "AllAllies", Amount = 0.10, Turns = 2 },
			{ Kind = "Cleanse", To = "AllAllies", Amount = 1 },
		},
		Description = "Acts at speed 80. Shield all allies for 10% of their max HP and remove one debuff each.",
	})

	-- Support class: team-wide buffs and healing.
	skill({
		Id = "sup_basic",
		Name = "Spark",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.3,
		Description = "Hit one enemy for 130% ATK.",
	})
	skill({
		Id = "sup_skill",
		Name = "Rally",
		Kind = "Skill",
		Cost = 1,
		Target = "AllAllies",
		Effects = {
			{ Kind = "StatMod", To = "AllAllies", Stat = "ATK", Amount = 0.25, Turns = 2 },
			{ Kind = "StatMod", To = "AllAllies", Stat = "CritRate", Amount = 0.10, Turns = 2 },
		},
		Description = "All allies gain 25% ATK and 10 points of crit chance for 2 turns.",
	})
	skill({
		Id = "sup_ult",
		Name = "Renewal",
		Kind = "Ultimate",
		Cost = 4,
		Target = "AllAllies",
		Effects = {
			{ Kind = "Heal", To = "AllAllies", Amount = 0.30 },
			{ Kind = "StatMod", To = "AllAllies", Stat = "DEF", Amount = 0.20, Turns = 2 },
		},
		Description = "Heal all allies for 30% of their max HP and raise their DEF by 20% for 2 turns.",
	})

	-- Disrupt class: enemy-wide debuffs, scaled by Effectiveness vs Resistance.
	skill({
		Id = "dis_basic",
		Name = "Hex Bolt",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.3,
		Description = "Hit one enemy for 130% ATK.",
	})
	skill({
		Id = "dis_skill",
		Name = "Sap",
		Kind = "Skill",
		Cost = 2,
		Target = "Enemy",
		Multiplier = 1.8,
		Effects = {
			{ Kind = "StatMod", To = "Target", Stat = "ATK", Amount = -0.20, Turns = 2, Scale = "Power" },
			{ Kind = "Energy", To = "Target", Amount = -1 },
		},
		Description = "Hit one enemy for 180% ATK, lower its ATK by 20% for 2 turns and drain 1 enemy energy.",
	})
	skill({
		Id = "dis_ult",
		Name = "Unravel",
		Kind = "Ultimate",
		Cost = 4,
		Target = "AllEnemies",
		Multiplier = 1.4,
		Effects = {
			{ Kind = "StatMod", To = "Target", Stat = "DEF", Amount = -0.30, Turns = 2, Scale = "Power" },
			{ Kind = "StatMod", To = "Target", Stat = "SPD", Amount = -0.15, Turns = 2, Scale = "Duration" },
		},
		Description = "Hit all enemies for 140% ATK, lower their DEF by 30% and Speed by 15% for 2 turns.",
	})

	-- Speed class: fast crits, counters, small self buffs.
	skill({
		Id = "spd_basic",
		Name = "Quick Cut",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.4,
		Description = "Hit one enemy for 140% ATK.",
	})
	skill({
		Id = "spd_skill",
		Name = "Blitz",
		Kind = "Skill",
		Cost = 2,
		Target = "Enemy",
		Multiplier = 2.5,
		Effects = { { Kind = "StatMod", To = "Self", Stat = "SPD", Amount = 0.20, Turns = 2 } },
		Description = "Hit one enemy for 250% ATK and raise own Speed by 20% for 2 turns.",
	})
	skill({
		Id = "spd_ult",
		Name = "Tempest",
		Kind = "Ultimate",
		Cost = 4,
		Target = "AllEnemies",
		Multiplier = 1.3,
		Effects = { { Kind = "StatMod", To = "Self", Stat = "CritRate", Amount = 0.15, Turns = 2 } },
		Description = "Hit all enemies for 130% ATK, then raise own crit chance by 15 points for 2 turns.",
	})
end

do
	passive({
		Id = "riposte",
		Name = "Riposte",
		Description = "20% chance to counter a single-target hit for 60% of a basic attack.",
		Counter = { Chance = 0.20, Multiplier = 0.6 },
	})
	passive({
		Id = "thorned_guard",
		Name = "Thorned Guard",
		Description = "While taunting, attackers lose 10% ATK for 1 turn.",
		OnHit = {
			WhileTaunting = true,
			Effects = {
				{ Kind = "StatMod", To = "Attacker", Stat = "ATK", Amount = -0.10, Turns = 1, Scale = "Power" },
			},
		},
	})
end

return {
	Skills = Skills,
	Passives = Passives,
}

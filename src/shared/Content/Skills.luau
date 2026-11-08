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

-- Launch 5-star kits (roadmap doc, "Character kits" tab). Names are placeholders until the
-- team renames them; signature gimmicks live in Combat/Kits.luau.
do
	-- Boku (Attack): each skill's first use fills a Power Meter segment.
	skill({
		Id = "boku_s1",
		Name = "Flash Punch",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.4,
		Description = "Flash forward and punch for 140% ATK. First use fills a Power Meter segment.",
	})
	skill({
		Id = "boku_s2",
		Name = "Breaker Rush",
		Kind = "Skill",
		Cost = 3,
		Target = "Enemy",
		Multiplier = 2.6,
		Description = "Hit one enemy for 260% ATK. First use fills a Power Meter segment.",
	})
	skill({
		Id = "boku_s3",
		Name = "Surge Cannon",
		Kind = "Ultimate",
		Cost = 5,
		Target = "Enemy",
		Multiplier = 3.0,
		Description = "Hit one enemy for 300% ATK. Fills the last segment. With a full meter after every ally has used their ultimate, he transforms.",
	})
	skill({
		Id = "boku_t1",
		Name = "Overdrive Jab",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 2.0,
		Description = "Hit one enemy for 200% ATK. Next round his skills deal +3% damage per energy they cost.",
	})
	skill({
		Id = "boku_t2",
		Name = "Overdrive Rush",
		Kind = "Skill",
		Cost = 5,
		Target = "Enemy",
		Multiplier = 3.0,
		Description = "Hit one enemy for 300% ATK. Next round his speed rolls at the top of his range.",
	})
	skill({
		Id = "boku_t3",
		Name = "Full Power Cannon",
		Kind = "Ultimate",
		Cost = 10,
		Target = "Enemy",
		Multiplier = 4.0,
		IgnoreDef = 0.5,
		NoCrit = true,
		Description = "Hit one enemy for 400% ATK, ignoring half its DEF. Can't crit. Locked for 1 round after transforming.",
	})

	-- Kojo (Defense): barrier tank with a lockdown and an auto-triggered unique.
	skill({
		Id = "kojo_s1",
		Name = "Repel",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.3,
		Description = "Hit one enemy for 130% ATK.",
	})
	skill({
		Id = "kojo_s2",
		Name = "Guarded Strike",
		Kind = "Skill",
		Cost = 2,
		Target = "Enemy",
		Multiplier = 1.8,
		Description = "Hit one enemy for 180% ATK. The most injured ally gets 15% damage reduction through next round.",
	})
	skill({
		Id = "kojo_s3",
		Name = "Stillness",
		Kind = "Ultimate",
		Cost = 7,
		Target = "AllEnemies",
		PrioritySpeed = 1,
		Cooldown = 3,
		Custom = true,
		Description = "Needs Skill 1 or 2 last round. Acts last. Cancelled (refund 3) if he takes 20% max HP first. Otherwise each enemy has a 75% stun chance and the enemy team gets half regen next round. 3-round cooldown.",
	})
	skill({
		Id = "kojo_unique",
		Name = "Breakpoint",
		Kind = "Skill",
		Cost = 0,
		Target = "AllEnemies",
		Multiplier = 2.0,
		Effects = { { Kind = "StatMod", To = "Self", Stat = "DEF", Amount = 0.5, Turns = 2 } },
		Description = "Auto-triggers. 200% ATK to all enemies, drops all his damage reduction and gives him +50% DEF for 2 rounds.",
	})

	-- Sasta (Defense, then Attack): Devil Seal tank who turns into a bleed attacker.
	skill({
		Id = "sasta_a1",
		Name = "Challenge",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		-- Acts at speed 100 for this move only; his Speed stat is untouched.
		PrioritySpeed = 100,
		Effects = {
			{ Kind = "Provoke", To = "Target", Turns = 1, ThisRound = true },
			{ Kind = "DamageReduction", To = "Self", Amount = 0.25, Turns = 1, ThisRound = true },
		},
		Description = "Acts first. One enemy must target him with its single-target moves this round; he takes 25% less damage this round.",
	})
	skill({
		Id = "sasta_a2",
		Name = "Null Cleave",
		Kind = "Skill",
		Cost = 3,
		Target = "Enemy",
		Multiplier = 2.0,
		PreEffects = { { Kind = "StripBuffs", To = "Target" } },
		Description = "Removes the target's damage-up and damage-reduction buffs, then hits it for 200% ATK.",
	})
	skill({
		Id = "sasta_a3",
		Name = "Devil Seal",
		Kind = "Ultimate",
		Cost = 7,
		Target = "Self",
		PrioritySpeed = 80,
		Effects = { { Kind = "Taunt", To = "Self", Turns = 1 } },
		Description = "Needs more than 35% HP. Acts first and taunts all enemies for 2 rounds; he can't act. Drop to 35% HP inside the window to transform; if it ends first, he loses a third of his HP and can't seal next round.",
	})
	skill({
		Id = "sasta_d1",
		Name = "Blood Sweep",
		Kind = "Skill",
		Cost = 2,
		Target = "AllEnemies",
		Multiplier = 0.7,
		Effects = { { Kind = "Bleed", To = "Target", Amount = 0.03, Count = 2 } },
		Description = "Hit all enemies for 70% ATK and apply Bleed 3 / 2. The first two uses each add +10% damage for the battle.",
	})
	skill({
		Id = "sasta_d2",
		Name = "Vengeance Stance",
		Kind = "Skill",
		Cost = 4,
		Target = "Self",
		PrioritySpeed = 80,
		Description = "Acts first. If a damaging attack hits him this round: +30% damage this round, enemies lose DEF buffs, and he counters every enemy for 12% of its max HP.",
	})
	skill({
		Id = "sasta_d3",
		Name = "Rupture",
		Kind = "Ultimate",
		Cost = 8,
		Target = "AllEnemies",
		Custom = true,
		Description = "Each enemy takes its bleed potency x count as % max HP (max 20%), then loses its bleed and blocks the next 2 bleed counts. No bleed anywhere: 10% max HP to all and -1 enemy energy.",
	})

	-- Shade (Speed): evasion and crit hunter who raises a fallen ally.
	skill({
		Id = "shade_s1",
		Name = "Shadow Step",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 1.4,
		Description = "Hit one enemy for 140% ATK. First use: +2 Speed and +10 crit for the battle.",
	})
	skill({
		Id = "shade_s2",
		Name = "Thousand Cuts",
		Kind = "Skill",
		Cost = 3,
		Target = "Enemy",
		Multiplier = 0.4,
		Pierce = true,
		Combo = { Guaranteed = 2, LandScale = { 2, 1, 0.5 }, CritBonus = 0.2, CritDamageBonus = 0.1 },
		Description = "2 to 5 piercing hits of 40% ATK. Hits 3-5 need luck (2x, 1x, then half his crit chance) and get +20 crit, +10% crit damage.",
	})
	skill({
		Id = "shade_s3",
		Name = "Raise Shadow",
		Kind = "Ultimate",
		Cost = 10,
		Target = "Self",
		PrioritySpeed = 999,
		Custom = true,
		Description = "Acts first. Once per battle, raises a fallen ally that hasn't revived as a shadow that strikes every round.",
	})
	skill({
		Id = "shade_shadow_strike",
		Name = "Shadow Strike",
		Kind = "Basic",
		Cost = 0,
		Target = "Enemy",
		Multiplier = 2.0,
		Pierce = true,
		Description = "Piercing hit on one enemy for 200% ATK.",
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
	passive({
		Id = "boku_power_meter",
		Name = "Power Meter",
		Description = "Each skill's first use: +5% ATK and +5 Speed for the battle. Full meter + every ally's ultimate used: Skill 3 transforms him (heal 50%, +5 energy, new skills).",
	})
	passive({
		Id = "kojo_barrier",
		Name = "Barrier",
		Description = "Starts at 75% damage reduction; -25% each round end, -5% per enemy hit. Taunts at 50%+. Skills 1 and 2 within 2 rounds while taking under 20% max HP triggers his unique.",
	})
	passive({
		Id = "sasta_seal",
		Name = "Devil Within",
		Description = "Devil Seal: reach 35% HP inside it to become an Attack unit at 80% HP (his one revive). Bleed: each hit on a bleeding enemy deals potency % of max HP and uses a count.",
	})
	passive({
		Id = "shade_shadow_step",
		Name = "Shadow Walker",
		Description = "Debuff immune in rounds 1-3. +4% evasion per round (max 40%). +1 crit per 3 speed above the target (max +20). A living shadow adds evasion and crit damage each round.",
	})
end

return {
	Skills = Skills,
	Passives = Passives,
}

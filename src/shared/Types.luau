--!strict
-- Shared type definitions for content and combat. Pure data, no Roblox APIs.

export type ClassName = "Attack" | "Defense" | "Support" | "Disrupt" | "Speed"

-- Relative stats (HP, ATK, DEF) scale by percent; the rest are additive fractions
-- (CritRate 0.2 = 20%, CritDamage 1.6 = 160%, EFF/RES 0.3 = 30 points).
export type StatName = "HP" | "ATK" | "DEF" | "SPD" | "CritRate" | "CritDamage" | "EFF" | "RES"

export type StatBlock = {
	HP: number,
	ATK: number,
	DEF: number,
	CritRate: number,
	CritDamage: number,
	EFF: number,
	RES: number,
}

export type SpeedRange = { Min: number, Max: number }

export type TargetKind = "Enemy" | "AllEnemies" | "Ally" | "AllAllies" | "Self"

-- "Target" = whoever the skill hit; "Attacker" is only valid inside OnHit passives;
-- "FallenAlly" = the first knocked-out ally that has not been revived yet.
export type EffectRecipient = "Target" | "Self" | "AllAllies" | "AllEnemies" | "Attacker" | "FallenAlly"

-- Burn: Amount = fraction of max HP lost at the end of each round (ignores DEF).
-- Stun: the unit skips its next action. EnergySteal: Amount energy moves to the caster's team.
-- Revive: brings a FallenAlly back with Amount of max HP (once per unit per battle).
-- DamageReduction: Amount of incoming damage removed. Provoke: the recipient's single-target
-- moves must target the source. StripBuffs: removes the recipient's ATK buffs and timed damage
-- reduction (or its DEF buffs when Stat = "DEF"). Bleed: Amount = potency (fraction of max HP
-- lost per damaging hit taken), Count = how many hits it lasts.
export type EffectSpec = {
	Kind: "StatMod"
		| "Taunt"
		| "Heal"
		| "Shield"
		| "Cleanse"
		| "Energy"
		| "Burn"
		| "Stun"
		| "EnergySteal"
		| "Revive"
		| "DamageReduction"
		| "Provoke"
		| "StripBuffs"
		| "Bleed",
	To: EffectRecipient?,
	Stat: StatName?,
	Amount: number?,
	Turns: number?,
	Count: number?,
	-- Debuffs only: which part Effectiveness/Resistance scales ("Chance" = landing chance).
	Scale: ("Power" | "Duration" | "Chance")?,
	Chance: number?,
	-- Chance is not scaled by Effectiveness/Resistance.
	Flat: boolean?,
	-- Lasts only until the end of the current round.
	ThisRound: boolean?,
}

-- Multi-hit move: the first Guaranteed hits always land, each later hit rolls
-- (crit chance + CritBonus) x LandScale[n] and needs the previous hit to have landed.
-- Hits after the guaranteed ones also get CritBonus and CritDamageBonus.
export type ComboSpec = {
	Guaranteed: number,
	LandScale: { number },
	CritBonus: number,
	CritDamageBonus: number,
}

export type SkillKind = "Basic" | "Skill" | "Ultimate"

export type SkillDef = {
	Id: string,
	Name: string,
	Kind: SkillKind,
	Cost: number,
	Target: TargetKind,
	Multiplier: number?,
	PrioritySpeed: number?,
	Effects: { EffectSpec }?,
	-- Extra hit on any target left below Threshold of max HP after the skill's hits.
	FollowUp: { Threshold: number, Multiplier: number }?,
	-- Applied to each target that the attack reaches, before the hit.
	PreEffects: { EffectSpec }?,
	Combo: ComboSpec?,
	-- Damage as a fraction of the target's max HP instead of ATK (ignores DEF, no crit).
	PercentMaxHP: number?,
	-- Fraction of the target's DEF ignored.
	IgnoreDef: number?,
	NoCrit: boolean?,
	-- Ignores timed damage reduction (not permanent reduction such as a barrier).
	Pierce: boolean?,
	-- Rounds the skill can't be used after a successful cast.
	Cooldown: number?,
	-- The character's kit resolves this skill itself (Kits.luau Cast hook).
	Custom: boolean?,
	Description: string,
}

export type PassiveDef = {
	Id: string,
	Name: string,
	Description: string,
	Counter: { Chance: number, Multiplier: number }?,
	OnHit: { WhileTaunting: boolean?, Effects: { EffectSpec } }?,
	-- Once per battle, come back with Health of max HP when knocked out.
	Revive: { Health: number }?,
}

export type CharacterDef = {
	Id: string,
	Name: string,
	Rarity: number,
	Class: ClassName,
	Stats: StatBlock,
	Speed: SpeedRange,
	EnergyRegen: number,
	Skills: { string },
	Passive: string?,
	Starter: boolean?,
	-- Signature-gimmick hooks in Combat/Kits.luau.
	Kit: string?,
}

export type ItemDef = {
	Id: string,
	Name: string,
	Stars: number,
	Bonuses: { [StatName]: number },
	Description: string,
}

-- One unit as it enters battle.
export type UnitLoadout = {
	Character: CharacterDef,
	Items: { ItemDef },
}

export type TeamLoadout = { UnitLoadout }

-- Saved team shape: character id plus equipped item ids.
export type TeamSlot = { Id: string, Items: { string } }

export type Action = { Skill: number, Target: number? }

return {}

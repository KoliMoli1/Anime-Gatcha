--!strict
-- Signature gimmicks for the launch 5-star kits (roadmap doc, "Character kits" tab).
-- BattleSession calls these hooks at fixed points; everything generic (evasion, bleed,
-- damage reduction, pierce, combos, cooldowns) lives in the engine.
--
-- Hooks take the session and unit untyped because this module loads before BattleSession.

local Types = require("../Types")
local Stats = require("./Stats")
local Classes = require("../Content/Classes")
local KitForms = require("../Content/KitForms")

type Session = any
type Unit = any

export type Kit = {
	Init: ((Session, Unit) -> ())?,
	RoundStart: ((Session, Unit) -> ())?,
	RoundEnd: ((Session, Unit) -> ())?,
	-- Return false plus a short reason to block a skill.
	CanUse: ((Session, Unit, number) -> (boolean?, string?))?,
	-- A move that replaces whatever was chosen this round (free).
	ForcedSkill: ((Session, Unit) -> Types.SkillDef?)?,
	-- Return false to stop the move after its cost is paid.
	BeforeAction: ((Session, Unit, Types.SkillDef) -> boolean?)?,
	AfterSkill: ((Session, Unit, Types.SkillDef, number, { Unit }) -> ())?,
	-- Resolves a skill marked Custom.
	Cast: ((Session, Unit, Types.SkillDef, { Unit }) -> ())?,
	OnHitTaken: ((Session, Unit, Unit) -> ())?,
	ClampHP: ((Session, Unit, number) -> number)?,
	AfterDamage: ((Session, Unit) -> ())?,
	DamageBonus: ((Session, Unit, Types.SkillDef?) -> number)?,
	CritBonus: ((Session, Unit, Unit) -> number)?,
	EvasionBonus: ((Session, Unit) -> number)?,
	IsTaunting: ((Session, Unit) -> boolean)?,
	ImmuneToDebuffs: ((Session, Unit) -> boolean)?,
	-- Short HUD lines both players see.
	Status: ((Session, Unit) -> { string })?,
	-- AI: preferred skill index (can(index) checks energy and availability), target, act first.
	AIChoose: ((Session, Unit, (number) -> boolean) -> number?)?,
	AITarget: ((Session, Unit, Types.SkillDef, { Unit }) -> Unit?)?,
	AIFirst: ((Session, Unit) -> boolean)?,
}

local Kits: { [string]: Kit } = {}

local function pct(value: number): string
	return `{math.floor(value * 100 + 0.5)}%`
end

local function kitEvent(session: Session, unit: Unit, text: string)
	session:_emit({ Type = "Kit", Side = unit.Side, Slot = unit.Slot, Text = text })
end

local function swapSkills(session: Session, unit: Unit, ids: { string })
	local skills = {}
	for index, id in ids do
		skills[index] = session:Skill(id)
	end
	unit.Skills = skills
end

local function highestAttack(session: Session, units: { Unit }): Unit?
	local best, bestAtk = nil, -1
	for _, unit in units do
		local atk = session:Effective(unit, "ATK")
		if atk > bestAtk then
			best, bestAtk = unit, atk
		end
	end
	return best
end

-- Boku (5-star Attack): Power Meter, then a once-per-battle transformation -------------

local BOKU_SEGMENTS = 3
local BOKU_SEGMENT_ATK = 0.05
local BOKU_SEGMENT_SPEED = 5
local BOKU_TRANSFORM_HEAL = 0.5
local BOKU_TRANSFORM_ENERGY = 5
local BOKU_COST_BONUS = 0.03
local BOKU_FORM = KitForms.Boku.Skills

local function bokuAlliesDone(session: Session, unit: Unit): (number, number)
	local done, total = 0, 0
	for _, ally in session.Teams[unit.Side].Units do
		if ally ~= unit then
			total += 1
			if not ally.Alive or ally.UltimateUsed or ally.IsShadow then
				done += 1
			end
		end
	end
	return done, total
end

local function bokuTransform(session: Session, unit: Unit)
	local kit = unit.Kit
	kit.Transformed = true
	kit.TransformRound = session.Round
	session:_emit({ Type = "Transform", Side = unit.Side, Slot = unit.Slot, Form = "Transformed" })
	session:_applyEffect(unit, unit, { Kind = "Heal", Amount = BOKU_TRANSFORM_HEAL }, "boku_transform:Heal")
	session:_applyEffect(unit, unit, { Kind = "Energy", Amount = BOKU_TRANSFORM_ENERGY }, "boku_transform:Energy")
	swapSkills(session, unit, BOKU_FORM)
end

Kits.Boku = {
	Init = function(_session, unit)
		unit.Kit.Meter = 0
		unit.Kit.Filled = {}
		unit.Kit.Transformed = false
	end,
	CanUse = function(session, unit, index)
		local kit = unit.Kit
		if kit.Transformed and index == 3 and session.Round <= kit.TransformRound + 1 then
			return false, "Charging"
		end
		return nil, nil
	end,
	AfterSkill = function(session, unit, skill, index)
		local kit = unit.Kit
		if not kit.Transformed then
			if index >= 1 and index <= BOKU_SEGMENTS and not kit.Filled[index] then
				kit.Filled[index] = true
				kit.Meter += 1
				unit.Perm.ATK += BOKU_SEGMENT_ATK
				unit.Base.SpeedMin += BOKU_SEGMENT_SPEED
				unit.Base.SpeedMax += BOKU_SEGMENT_SPEED
				kitEvent(session, unit, `Power Meter {kit.Meter}/{BOKU_SEGMENTS}`)
			end
			if skill.Id == "boku_s3" and kit.Meter >= BOKU_SEGMENTS then
				local done, total = bokuAlliesDone(session, unit)
				if done >= total then
					bokuTransform(session, unit)
				end
			end
		elseif skill.Id == "boku_t1" then
			kit.BonusRound = session.Round + 1
		elseif skill.Id == "boku_t2" then
			kit.MaxSpeedRound = session.Round + 1
		end
	end,
	RoundStart = function(session, unit)
		if unit.Kit.MaxSpeedRound == session.Round then
			unit.Speed = math.floor(Stats.apply("SPD", unit.Base.SpeedMax, session:Modifier(unit, "SPD")) + 0.5)
		end
	end,
	DamageBonus = function(session, unit, skill)
		if skill and unit.Kit.BonusRound == session.Round then
			return 1 + BOKU_COST_BONUS * skill.Cost
		end
		return 1
	end,
	Status = function(session, unit)
		local kit = unit.Kit
		local lines = {}
		if kit.Transformed then
			table.insert(lines, "Transformed")
			if session.Round <= kit.TransformRound + 1 then
				table.insert(lines, "Full Power: charging")
			else
				table.insert(lines, "FULL POWER READY")
			end
			if kit.BonusRound == session.Round then
				table.insert(lines, "This round: stronger big moves")
			end
			if kit.MaxSpeedRound == session.Round then
				table.insert(lines, "This round: top speed")
			end
		else
			local done, total = bokuAlliesDone(session, unit)
			table.insert(
				lines,
				`Power Meter {kit.Meter}/{BOKU_SEGMENTS} (+{pct(kit.Meter * BOKU_SEGMENT_ATK)} ATK, +{kit.Meter * BOKU_SEGMENT_SPEED} Speed)`
			)
			table.insert(lines, `Allies' ultimates: {done}/{total}`)
			local missing = (BOKU_SEGMENTS - kit.Meter) + (total - done)
			local s3Fills = kit.Meter == BOKU_SEGMENTS - 1 and not kit.Filled[3]
			if done >= total and (kit.Meter >= BOKU_SEGMENTS or s3Fills) then
				table.insert(lines, "READY: his next Skill 3 transforms him")
			elseif missing == 1 then
				table.insert(lines, "One step away from transforming")
			end
		end
		return lines
	end,
	AIChoose = function(_session, unit, can)
		local kit = unit.Kit
		if kit.Transformed then
			-- Save the pool for Full Power; the free move also boosts it.
			return if can(3) then 3 else 1
		end
		if can(3) and kit.Filled[1] and kit.Filled[2] then
			return 3
		end
		if not kit.Filled[1] then
			return 1
		end
		if can(2) then
			return 2
		end
		return 1
	end,
	AIFirst = function(session, unit)
		return unit.Kit.Transformed and session:CanUse(unit, 3) and session.Teams[unit.Side].Energy >= 10
	end,
}

-- Kojo (5-star Defense): decaying barrier, taunt, lockdown and an auto-triggered unique -----

local KOJO_BARRIER_KEY = "kojo_barrier"
local KOJO_BARRIER_START = 0.75
local KOJO_BARRIER_ROUND_DECAY = 0.25
local KOJO_BARRIER_HIT_DECAY = 0.05
local KOJO_TAUNT_AT = 0.5
local KOJO_DAMAGE_LIMIT = 0.2
local KOJO_CANCEL_REFUND = 3
local KOJO_STUN_CHANCE = 0.75
local KOJO_ALLY_REDUCTION = 0.15
local KOJO_REPEAT_REDUCTION = 0.2

local function kojoBarrier(session: Session, unit: Unit): any
	for _, effect in unit.Effects do
		if effect.Key == KOJO_BARRIER_KEY then
			return effect
		end
	end
	local _ = session
	return nil
end

local function kojoDecay(session: Session, unit: Unit, amount: number)
	local barrier = kojoBarrier(session, unit)
	if barrier then
		barrier.Amount = math.max(0, barrier.Amount - amount)
		if barrier.Amount <= 1e-9 then
			session:RemoveEffect(unit, barrier)
			kitEvent(session, unit, "Barrier broken")
		end
	end
end

local function kojoLimit(unit: Unit): number
	return math.floor(unit.MaxHP * KOJO_DAMAGE_LIMIT + 0.5)
end

-- Skill indices used in the two rounds before this one, after the last unique trigger.
local function kojoRecent(session: Session, unit: Unit): { [number]: boolean }
	local used = {}
	local after = unit.Kit.WindowStart or 0
	for round = session.Round - 2, session.Round - 1 do
		local index = unit.History[round]
		if round > after and index then
			used[index] = true
		end
	end
	return used
end

Kits.Kojo = {
	Init = function(_session, unit)
		table.insert(unit.Effects, {
			Kind = "DamageReduction",
			Key = KOJO_BARRIER_KEY,
			Amount = KOJO_BARRIER_START,
			Turns = 1,
			Debuff = false,
			Fresh = false,
			Permanent = true,
			Unremovable = true,
		})
	end,
	IsTaunting = function(session, unit)
		local barrier = kojoBarrier(session, unit)
		return barrier ~= nil and barrier.Amount >= KOJO_TAUNT_AT - 1e-9
	end,
	OnHitTaken = function(session, unit)
		kojoDecay(session, unit, KOJO_BARRIER_HIT_DECAY)
	end,
	RoundEnd = function(session, unit)
		kojoDecay(session, unit, KOJO_BARRIER_ROUND_DECAY)
	end,
	RoundStart = function(session, unit)
		local used = kojoRecent(session, unit)
		local took = unit.DamageTaken[session.Round - 1] or 0
		if used[1] and used[2] and took < kojoLimit(unit) then
			unit.Kit.WindowStart = session.Round - 1
			if not unit.Kit.UniqueUsed then
				unit.Kit.UniqueReady = true
				kitEvent(session, unit, "Unique ready: it replaces this round's move")
			else
				session:_applyEffect(
					unit,
					unit,
					{ Kind = "DamageReduction", Amount = KOJO_REPEAT_REDUCTION, Turns = 1, ThisRound = true },
					"kojo_repeat:DamageReduction"
				)
			end
		end
	end,
	ForcedSkill = function(session, unit)
		return if unit.Kit.UniqueReady then session:Skill("kojo_unique") else nil
	end,
	CanUse = function(session, unit, index)
		if unit.Skills[index].Id == "kojo_s3" then
			local last = unit.History[session.Round - 1]
			if last ~= 1 and last ~= 2 then
				return false, "Needs Skill 1 or 2 last round"
			end
		end
		return nil, nil
	end,
	BeforeAction = function(session, unit, skill)
		if skill.Id == "kojo_s3" and (unit.DamageTaken[session.Round] or 0) >= kojoLimit(unit) then
			local team = session.Teams[unit.Side]
			team.Energy = math.min(10, team.Energy + KOJO_CANCEL_REFUND)
			session:_emit({
				Type = "Cancelled",
				Side = unit.Side,
				Slot = unit.Slot,
				SkillName = skill.Name,
				Refund = KOJO_CANCEL_REFUND,
				Energy = team.Energy,
			})
			return false
		end
		return nil
	end,
	Cast = function(session, unit, skill)
		local enemySide = 3 - unit.Side
		for _, enemy in session:Living(enemySide) do
			if session:_attackLands(unit, enemy) then
				session:_applyEffect(
					unit,
					enemy,
					{ Kind = "Stun", Chance = KOJO_STUN_CHANCE, Flat = true, Turns = 1 },
					`{skill.Id}:Stun`
				)
			end
		end
		session.Teams[enemySide].HalfRegenRound = session.Round + 1
		kitEvent(session, unit, "Enemy energy regen halved next round")
	end,
	AfterSkill = function(session, unit, skill)
		if skill.Id == "kojo_unique" then
			unit.Kit.UniqueReady = false
			unit.Kit.UniqueUsed = true
			for index = #unit.Effects, 1, -1 do
				if unit.Effects[index].Kind == "DamageReduction" then
					session:RemoveEffect(unit, unit.Effects[index])
				end
			end
		elseif skill.Id == "kojo_s2" then
			local best: Unit = nil
			for _, ally in session:Living(unit.Side) do
				if ally ~= unit and (not best or ally.HP / ally.MaxHP < best.HP / best.MaxHP) then
					best = ally
				end
			end
			session:_applyEffect(
				unit,
				best or unit,
				{ Kind = "DamageReduction", Amount = KOJO_ALLY_REDUCTION, Turns = 1 },
				"kojo_s2:DamageReduction"
			)
		end
	end,
	Status = function(session, unit)
		local lines = {}
		local barrier = kojoBarrier(session, unit)
		if barrier then
			local taunt = if barrier.Amount >= KOJO_TAUNT_AT - 1e-9 then " · taunting" else ""
			table.insert(lines, `Barrier {pct(barrier.Amount)}{taunt}`)
		end
		if unit.Kit.UniqueReady then
			table.insert(lines, "UNIQUE READY: replaces this round's move")
		else
			local used = kojoRecent(session, unit)
			local s1 = if used[1] then "done" else "-"
			local s2 = if used[2] then "done" else "-"
			local unique = if unit.Kit.UniqueUsed then "Repeat" else "Unique"
			table.insert(lines, `{unique}: S1 {s1} S2 {s2}`)
		end
		table.insert(lines, `Damage this round {unit.DamageTaken[session.Round] or 0}/{kojoLimit(unit)}`)
		return lines
	end,
	AIChoose = function(session, unit, can)
		local enemies = session:Living(3 - unit.Side)
		if can(3) and #enemies >= 2 then
			return 3
		end
		local last = unit.History[session.Round - 1]
		if last == 1 and can(2) then
			return 2
		end
		return 1
	end,
}

-- Sasta (5-star Defense, transforms into Attack): Devil Seal, bleed and counters --------

local SASTA_THRESHOLD = 0.35
local SASTA_TRANSFORM_HP = 0.8
local SASTA_SWEEP_STEP = 0.1
local SASTA_SWEEP_STACKS = 2
local SASTA_STANCE_BONUS = 1.3
local SASTA_COUNTER = 0.12
local SASTA_RUPTURE_CAP = 0.2
local SASTA_RUPTURE_FLAT = 0.1
local SASTA_IMMUNITY = 2
local SASTA_DRAIN_CAP = 2
local SASTA_FAIL_COST = 1 / 3
local SASTA_FAIL_COOLDOWN = 1
local SASTA_FORM = KitForms.Sasta.Skills

local function sastaThreshold(unit: Unit): number
	return math.floor(unit.MaxHP * SASTA_THRESHOLD + 0.5)
end

local function sastaSealed(session: Session, unit: Unit): boolean
	local kit = unit.Kit
	return kit.SealUntil ~= nil and session.Round <= kit.SealUntil and not kit.Transformed
end

local function sastaTransform(session: Session, unit: Unit)
	local kit = unit.Kit
	kit.Transformed = true
	kit.TransformPending = false
	kit.SealUntil = nil
	unit.ReviveUsed = true
	for index = #unit.Effects, 1, -1 do
		if unit.Effects[index].Kind == "Taunt" then
			table.remove(unit.Effects, index)
		end
	end
	-- Every stat but max HP becomes the Attack class's.
	local form = table.clone(unit.Def)
	local stats = Classes.statsFor("Attack", unit.Def.Rarity)
	stats.HP = unit.Def.Stats.HP
	form.Stats = stats
	form.Speed = Classes.speedFor("Attack", unit.Def.Rarity)
	form.Class = "Attack"
	unit.Base = Stats.withItems(form, unit.Items)
	unit.Class = "Attack"
	unit.EnergyRegen = Classes.Templates[unit.Class :: Types.ClassName].EnergyRegen
	unit.HP = math.floor(unit.MaxHP * SASTA_TRANSFORM_HP + 0.5)
	swapSkills(session, unit, SASTA_FORM)
	session:_emit({ Type = "Transform", Side = unit.Side, Slot = unit.Slot, Form = "Devil", HP = unit.HP })
end

local function sastaBleedTotal(session: Session, unit: Unit): number
	local total = 0
	for _, enemy in session:Living(3 - unit.Side) do
		local bleed = session:FindEffect(enemy, "Bleed")
		if bleed then
			total += bleed.Amount * (bleed.Count or 0)
		end
	end
	return total
end

Kits.Sasta = {
	CanUse = function(session, unit, index)
		local kit = unit.Kit
		if sastaSealed(session, unit) and session.Round > kit.SealRound and index ~= 1 then
			return false, "Sealed"
		end
		if not kit.Transformed and index == 3 and unit.HP <= sastaThreshold(unit) then
			return false, "Needs more than 35% HP"
		end
		return nil, nil
	end,
	BeforeAction = function(session, unit)
		local kit = unit.Kit
		if sastaSealed(session, unit) and session.Round > kit.SealRound then
			session:_emit({ Type = "Sealed", Side = unit.Side, Slot = unit.Slot })
			return false
		end
		return nil
	end,
	AfterSkill = function(session, unit, skill)
		local kit = unit.Kit
		if skill.Id == "sasta_a3" then
			kit.SealRound = session.Round
			kit.SealUntil = session.Round + 1
			kitEvent(session, unit, `Devil Seal: transforms at {sastaThreshold(unit)} HP within 2 rounds`)
		elseif skill.Id == "sasta_d2" then
			kit.StanceRound = session.Round
			kit.StanceFired = false
		end
	end,
	ClampHP = function(session, unit, newHP)
		if sastaSealed(session, unit) then
			local threshold = sastaThreshold(unit)
			if newHP <= threshold then
				unit.Kit.TransformPending = true
				return threshold
			end
		end
		return newHP
	end,
	AfterDamage = function(session, unit)
		if unit.Kit.TransformPending then
			sastaTransform(session, unit)
		end
	end,
	RoundEnd = function(session, unit)
		local kit = unit.Kit
		if kit.SealUntil == session.Round and not kit.Transformed then
			-- A failed seal costs a third of his current HP and locks the seal for a round.
			kit.SealUntil = nil
			local cost = math.floor(unit.HP * SASTA_FAIL_COST + 0.5)
			unit.HP = math.max(1, unit.HP - cost)
			unit.Cooldowns.sasta_a3 = session.Round + SASTA_FAIL_COOLDOWN
			kitEvent(session, unit, `The Devil Seal failed: lost {cost} HP`)
		end
	end,
	OnHitTaken = function(session, unit)
		local kit = unit.Kit
		if kit.StanceRound ~= session.Round or kit.StanceFired then
			return
		end
		kit.StanceFired = true
		kit.StanceBonusRound = session.Round
		session:_emit({ Type = "Counter", Side = unit.Side, Slot = unit.Slot })
		for _, enemy in session:Living(3 - unit.Side) do
			session:_applyEffect(unit, enemy, { Kind = "StripBuffs", Stat = "DEF" }, "sasta_d2:StripBuffs")
		end
		for _, enemy in session:Living(3 - unit.Side) do
			session:CounterPercent(unit, enemy, SASTA_COUNTER)
		end
	end,
	DamageBonus = function(session, unit, skill)
		local bonus = 1
		if skill and skill.Id == "sasta_d1" then
			bonus *= 1 + SASTA_SWEEP_STEP * math.min(unit.Uses.sasta_d1 or 0, SASTA_SWEEP_STACKS)
		end
		if unit.Kit.StanceBonusRound == session.Round then
			bonus *= SASTA_STANCE_BONUS
		end
		return bonus
	end,
	Cast = function(session, unit, skill)
		local kit = unit.Kit
		local enemies = session:Living(3 - unit.Side)
		local anyBleed = sastaBleedTotal(session, unit) > 0
		for _, enemy in enemies do
			if session:_attackLands(unit, enemy) then
				local fraction = if anyBleed then 0 else SASTA_RUPTURE_FLAT
				local bleed = session:FindEffect(enemy, "Bleed")
				if bleed then
					fraction = math.min(SASTA_RUPTURE_CAP, bleed.Amount * (bleed.Count or 0))
					session:RemoveEffect(enemy, bleed)
				end
				if fraction > 0 then
					local amount =
						math.max(1, math.floor(enemy.MaxHP * fraction * session:_damageBonus(unit, skill) + 0.5))
					session:_dealDamage(enemy, amount, { Type = "Damage", Source = unit })
				end
				if enemy.Alive and anyBleed then
					session.AddOrRefresh(enemy, {
						Kind = "BleedImmune",
						Key = "bleed_immunity",
						Amount = 0,
						Count = SASTA_IMMUNITY,
						Turns = 1,
						Debuff = false,
						Fresh = true,
						Permanent = true,
					})
				end
			end
		end
		if not anyBleed and (kit.Drained or 0) < SASTA_DRAIN_CAP then
			local team = session.Teams[3 - unit.Side]
			if team.Energy > 0 then
				kit.Drained = (kit.Drained or 0) + 1
				team.Energy -= 1
				session:_emit({
					Type = "Effect",
					Kind = "Energy",
					Side = 3 - unit.Side,
					Slot = 1,
					Key = `{skill.Id}:Energy`,
					Amount = -1,
					Energy = team.Energy,
				})
			end
		end
	end,
	Status = function(session, unit)
		local kit = unit.Kit
		local lines = {}
		if kit.Transformed then
			table.insert(lines, "Devil form")
			local stacks = math.min(unit.Uses.sasta_d1 or 0, SASTA_SWEEP_STACKS)
			if stacks > 0 then
				table.insert(lines, `Blood Sweep +{pct(stacks * SASTA_SWEEP_STEP)}`)
			end
			if kit.StanceRound == session.Round and not kit.StanceFired then
				table.insert(lines, "Counter stance up")
			end
			table.insert(lines, `Energy drained {kit.Drained or 0}/{SASTA_DRAIN_CAP}`)
		elseif sastaSealed(session, unit) then
			local left = kit.SealUntil - session.Round + 1
			table.insert(
				lines,
				`DEVIL SEAL: {left} round{if left == 1 then "" else "s"} left · transforms at {sastaThreshold(unit)} HP`
			)
		else
			table.insert(lines, `Devil Seal needs more than {sastaThreshold(unit)} HP`)
		end
		return lines
	end,
	AIChoose = function(session, unit, can)
		local kit = unit.Kit
		if kit.Transformed then
			if can(3) and sastaBleedTotal(session, unit) >= 0.15 then
				return 3
			end
			if can(1) then
				return 1
			end
			return if can(2) then 2 else 1
		end
		if sastaSealed(session, unit) then
			return 1
		end
		if can(3) and session.Round >= 2 and unit.HP / unit.MaxHP > 0.7 then
			return 3
		end
		for _, enemy in session:Living(3 - unit.Side) do
			for _, effect in enemy.Effects do
				local buffed = (effect.Kind == "StatMod" and effect.Stat == "ATK" and effect.Amount > 0)
					or (effect.Kind == "DamageReduction" and not effect.Unremovable)
				if buffed and can(2) then
					return 2
				end
			end
		end
		return 1
	end,
	AITarget = function(session, unit, skill, enemies)
		if skill.Id == "sasta_a1" then
			return highestAttack(session, enemies)
		end
		if skill.Id == "sasta_a2" then
			for _, enemy in enemies do
				for _, effect in enemy.Effects do
					if
						(effect.Kind == "StatMod" and effect.Stat == "ATK" and effect.Amount > 0)
						or (effect.Kind == "DamageReduction" and not effect.Unremovable)
					then
						return enemy
					end
				end
			end
		end
		local _ = unit
		return nil
	end,
}

-- Shade (5-star Speed): evasion, speed-gap crits, combo hits and a raised shadow --------

local SHADE_IMMUNE_ROUNDS = 3
local SHADE_EVASION_STEP = 0.04
local SHADE_EVASION_CAP = 0.4
local SHADE_SHADOW_EVASION_STEP = 0.05
local SHADE_SHADOW_EVASION_CAP = 0.2
local SHADE_SHADOW_CRIT_STEP = 0.1
local SHADE_SHADOW_CRIT_CAP = 0.3
local SHADE_GAP_STEP = 3
local SHADE_GAP_CAP = 0.2
local SHADE_FIRST_SPEED = 2
local SHADE_FIRST_CRIT = 0.1
local SHADOW_STATS = { HP = 200, ATK = 90, DEF = 25, CritRate = 0.2, CritDamage = 1.5, EFF = 0, RES = 0 }
local SHADOW_EVASION = 0.3

local function shadeShadow(session: Session, unit: Unit): Unit?
	for _, ally in session.Teams[unit.Side].Units do
		if ally.IsShadow and ally.Alive and ally.Kit.MasterSlot == unit.Slot then
			return ally
		end
	end
	return nil
end

local function shadeFallen(session: Session, unit: Unit): Unit?
	for _, ally in session.Teams[unit.Side].Units do
		if not ally.Alive and not ally.ReviveUsed then
			return ally
		end
	end
	return nil
end

local function raiseShadow(session: Session, master: Unit, ally: Unit)
	ally.IsShadow = true
	ally.ReviveUsed = true
	ally.UltimateUsed = true
	ally.Alive = true
	ally.Effects = {}
	ally.Name = `Shadow {ally.Def.Name}`
	ally.Passive = nil
	ally.EnergyRegen = 0
	ally.NoHeal = true
	ally.Evasion = SHADOW_EVASION
	ally.Perm = { ATK = 0, CritRate = 0, CritDamage = 0 }
	ally.Cooldowns = {}
	ally.History = {}
	local base = table.clone(SHADOW_STATS) :: any
	base.SpeedMin = master.Base.SpeedMin
	base.SpeedMax = master.Base.SpeedMax
	ally.Base = base
	ally.MaxHP = SHADOW_STATS.HP
	ally.HP = SHADOW_STATS.HP
	ally.KitId = "Shadow"
	ally.Kit = { MasterSlot = master.Slot }
	swapSkills(session, ally, KitForms.Shade.Skills)
	session:_emit({ Type = "Shadow", Side = ally.Side, Slot = ally.Slot, HP = ally.HP, Name = ally.Name })
end

Kits.Shade = {
	Init = function(_session, unit)
		unit.Kit.OwnEvasion = 0
		unit.Kit.ShadowEvasion = 0
		unit.Kit.ShadowCrit = 0
	end,
	RoundStart = function(session, unit)
		local kit = unit.Kit
		kit.OwnEvasion = math.min(SHADE_EVASION_CAP, kit.OwnEvasion + SHADE_EVASION_STEP)
		if shadeShadow(session, unit) then
			kit.ShadowEvasion = math.min(SHADE_SHADOW_EVASION_CAP, kit.ShadowEvasion + SHADE_SHADOW_EVASION_STEP)
			local crit = math.min(SHADE_SHADOW_CRIT_CAP, kit.ShadowCrit + SHADE_SHADOW_CRIT_STEP)
			unit.Perm.CritDamage += crit - kit.ShadowCrit
			kit.ShadowCrit = crit
		end
	end,
	ImmuneToDebuffs = function(session)
		return session.Round <= SHADE_IMMUNE_ROUNDS
	end,
	EvasionBonus = function(_session, unit)
		return unit.Kit.OwnEvasion + unit.Kit.ShadowEvasion
	end,
	CritBonus = function(_session, unit, target)
		local gap = unit.Speed - (target.Speed or 0)
		if gap < SHADE_GAP_STEP then
			return 0
		end
		return math.min(SHADE_GAP_CAP, math.floor(gap / SHADE_GAP_STEP) * 0.01)
	end,
	CanUse = function(session, unit, index)
		if unit.Skills[index].Id == "shade_s3" then
			if unit.Kit.ShadowUsed then
				return false, "Once per battle"
			end
			if not shadeFallen(session, unit) then
				return false, "Needs a fallen ally that hasn't revived"
			end
		end
		return nil, nil
	end,
	Cast = function(session, unit)
		local ally = shadeFallen(session, unit)
		if ally then
			unit.Kit.ShadowUsed = true
			raiseShadow(session, unit, ally)
		end
	end,
	AfterSkill = function(_session, unit, skill)
		if skill.Id == "shade_s1" and not unit.Uses.shade_s1 then
			unit.Base.SpeedMin += SHADE_FIRST_SPEED
			unit.Base.SpeedMax += SHADE_FIRST_SPEED
			unit.Perm.CritRate += SHADE_FIRST_CRIT
		end
	end,
	Status = function(session, unit)
		local kit = unit.Kit
		local lines = {}
		if session.Round <= SHADE_IMMUNE_ROUNDS then
			local left = SHADE_IMMUNE_ROUNDS - session.Round + 1
			table.insert(lines, `Debuff immune: {left} round{if left == 1 then "" else "s"}`)
		end
		table.insert(lines, "+Crit vs slower targets")
		if kit.ShadowCrit > 0 then
			table.insert(lines, `Shadow bonus: +{pct(kit.ShadowEvasion)} evasion, +{pct(kit.ShadowCrit)} crit DMG`)
		end
		return lines
	end,
	AIChoose = function(_session, _unit, can)
		if can(3) then
			return 3
		end
		return if can(2) then 2 else 1
	end,
	AIFirst = function(session, unit)
		return session:CanUse(unit, 3) and session.Teams[unit.Side].Energy >= 10
	end,
}

-- A raised shadow moves at its master's speed.
Kits.Shadow = {
	RoundStart = function(session, unit)
		local master = session.Teams[unit.Side].Units[unit.Kit.MasterSlot]
		if master and master.Alive then
			unit.Speed = master.Speed
		end
	end,
	Status = function()
		return { "Shadow: can't be healed" }
	end,
	AIChoose = function()
		return 1
	end,
}

return Kits

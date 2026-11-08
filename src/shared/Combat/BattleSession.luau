--!strict
-- Server-authoritative 3v3 battle. Pure Luau: runs in Studio and in Lune.
--
-- Round flow: BeginRound (energy regen, speed rolls) -> both sides Submit ->
-- Resolve (speed-ordered actions) -> EndRound (effect timers) -> next BeginRound.
-- Every change is reported as an ordered event list for clients to play back.
-- Character signature gimmicks live in Kits.luau and hook in at the points marked "kit".

local Types = require("../Types")
local Rng = require("../Util/Rng")
local Stats = require("./Stats")
local Kits = require("./Kits")
local SkillContent = require("../Content/Skills")

local BattleSession = {}
BattleSession.__index = BattleSession

BattleSession.MAX_ENERGY = 10
BattleSession.START_ENERGY = 3
BattleSession.DEFAULT_MAX_ROUNDS = 30
-- Overtime: from this round on, all damage grows by OVERTIME_STEP per round (cumulative).
BattleSession.OVERTIME_START = 9
BattleSession.OVERTIME_STEP = 0.15
-- Burn can never take more than this share of max HP per round, after scaling.
BattleSession.BURN_CAP = 0.12
-- After a stun is used up, the unit can't be stunned again for this many rounds.
BattleSession.STUN_IMMUNITY_TURNS = 1
-- Evasion and damage reduction caps for any unit.
BattleSession.EVASION_CAP = 0.8
BattleSession.REDUCTION_CAP = 0.9
-- Bleed: reapplying adds potency and count up to these caps.
BattleSession.BLEED_POTENCY_STEP = 0.03
BattleSession.BLEED_POTENCY_CAP = 0.09
BattleSession.BLEED_COUNT_CAP = 4
-- Action.Skill = REST skips the unit's turn (for units whose cheapest move costs energy).
BattleSession.REST = 0

export type Effect = {
	Kind: "StatMod"
		| "Taunt"
		| "Shield"
		| "Burn"
		| "Stun"
		| "StunImmune"
		| "DamageReduction"
		| "Provoke"
		| "Bleed"
		| "BleedImmune",
	Key: string,
	Stat: Types.StatName?,
	Amount: number,
	Turns: number,
	Debuff: boolean,
	Fresh: boolean,
	-- Never ticks down (bleed, barriers); removed by its own rules.
	Permanent: boolean?,
	-- Not removed by StripBuffs.
	Unremovable: boolean?,
	-- Bleed hits left, or bleed counts blocked for BleedImmune.
	Count: number?,
	-- Provoke: the unit that must be targeted.
	SourceSide: number?,
	SourceSlot: number?,
}

export type Unit = {
	Side: number,
	Slot: number,
	Def: Types.CharacterDef,
	Items: { Types.ItemDef },
	Name: string,
	Class: Types.ClassName,
	Base: Stats.BattleStats,
	HP: number,
	MaxHP: number,
	Alive: boolean,
	Effects: { Effect },
	Speed: number,
	Tiebreak: number,
	Skills: { Types.SkillDef },
	Passive: Types.PassiveDef?,
	-- Revives (passive, skill, transformation or shadow) are once per unit per battle.
	ReviveUsed: boolean,
	EnergyRegen: number,
	-- Permanent battle bonuses outside the +/-50% cap (ATK is relative, the rest are points).
	Perm: { ATK: number, CritRate: number, CritDamage: number },
	Evasion: number,
	-- The first attack aimed at a unit each round rolls its evasion; later ones always land.
	DodgeRolled: boolean,
	-- Uses[skillId] = times used; History[round] = skill index used that round.
	Uses: { [string]: number },
	History: { [number]: number },
	UltimateUsed: boolean,
	-- Cooldowns[skillId] = last round the skill is still unusable.
	Cooldowns: { [string]: number },
	-- DamageTaken[round] = damage after DEF, before damage reduction and shields.
	DamageTaken: { [number]: number },
	NoHeal: boolean,
	IsShadow: boolean,
	KitId: string?,
	Kit: { [string]: any },
}

export type Team = {
	Units: { Unit },
	Energy: number,
	Actions: { [number]: Types.Action }?,
	-- Round in which this team's energy regen is halved.
	HalfRegenRound: number?,
}

export type Event = { [string]: any }

export type Config = {
	Seed: number,
	Teams: { Types.TeamLoadout },
	MaxRounds: number?,
	Skills: { [string]: Types.SkillDef }?,
	Passives: { [string]: Types.PassiveDef }?,
}

export type Session = typeof(setmetatable(
	{} :: {
		Teams: { Team },
		Round: number,
		MaxRounds: number,
		Phase: "Choosing" | "Finished",
		Winner: number?,
		EndReason: string?,
		Rng: Rng.Rng,
		SkillDefs: { [string]: Types.SkillDef },
		_events: { Event },
	},
	BattleSession
))

export type HitOptions = {
	Single: boolean,
	IsCounter: boolean?,
	Skill: Types.SkillDef?,
	CritBonus: number?,
	CritDamageBonus: number?,
	-- The dodge roll for this attack was already made.
	SkipDodge: boolean?,
}

local function makeUnit(
	side: number,
	slot: number,
	loadout: Types.UnitLoadout,
	skills: { [string]: Types.SkillDef },
	passives: { [string]: Types.PassiveDef }
): Unit
	local def = loadout.Character
	local base = Stats.withItems(def, loadout.Items)
	local unitSkills = {}
	for index, skillId in def.Skills do
		unitSkills[index] = assert(skills[skillId], `Unknown skill {skillId} on {def.Id}`)
	end
	return {
		Side = side,
		Slot = slot,
		Def = def,
		Items = loadout.Items,
		Name = def.Name,
		Class = def.Class,
		Base = base,
		HP = base.HP,
		MaxHP = base.HP,
		Alive = true,
		Effects = {},
		Speed = 0,
		Tiebreak = 0,
		Skills = unitSkills,
		Passive = def.Passive and passives[def.Passive] or nil,
		ReviveUsed = false,
		EnergyRegen = def.EnergyRegen,
		Perm = { ATK = 0, CritRate = 0, CritDamage = 0 },
		Evasion = 0,
		DodgeRolled = false,
		Uses = {},
		History = {},
		UltimateUsed = false,
		Cooldowns = {},
		DamageTaken = {},
		NoHeal = false,
		IsShadow = false,
		KitId = def.Kit,
		Kit = {},
	}
end

function BattleSession.new(config: Config): Session
	assert(#config.Teams == 2, "A battle needs two teams")
	local skills = config.Skills or SkillContent.Skills
	local passives = config.Passives or SkillContent.Passives
	local teams = {}
	for side, loadout in config.Teams do
		assert(#loadout == 3, "Each team needs three units")
		local units = {}
		for slot, unitLoadout in loadout do
			units[slot] = makeUnit(side, slot, unitLoadout, skills, passives)
		end
		teams[side] = { Units = units, Energy = BattleSession.START_ENERGY, Actions = nil }
	end
	local self = setmetatable({
		Teams = teams,
		Round = 0,
		MaxRounds = config.MaxRounds or BattleSession.DEFAULT_MAX_ROUNDS,
		Phase = "Choosing" :: "Choosing" | "Finished",
		Winner = nil :: number?,
		EndReason = nil :: string?,
		Rng = Rng.new(config.Seed),
		SkillDefs = skills,
		_events = {},
	}, BattleSession)
	for _, team in self.Teams do
		for _, unit in team.Units do
			local kit = self:KitOf(unit)
			if kit and kit.Init then
				kit.Init(self, unit)
			end
		end
	end
	self:_beginRound()
	return self
end

-- Drains events produced since the last call (construction emits the first RoundStart).
function BattleSession.TakeEvents(self: Session): { Event }
	local events = self._events
	self._events = {}
	return events
end

function BattleSession._emit(self: Session, event: Event)
	table.insert(self._events, event)
end

function BattleSession.KitOf(_self: Session, unit: Unit): Kits.Kit?
	return if unit.KitId then Kits[unit.KitId] else nil
end

function BattleSession.Skill(self: Session, id: string): Types.SkillDef
	return assert(self.SkillDefs[id], `Unknown skill {id}`)
end

-- Stats ---------------------------------------------------------------------------

function BattleSession.Modifier(_self: Session, unit: Unit, stat: Types.StatName): number
	local total = 0
	for _, effect in unit.Effects do
		if effect.Kind == "StatMod" and effect.Stat == stat then
			total += effect.Amount
		end
	end
	return total
end

function BattleSession.Effective(self: Session, unit: Unit, stat: Types.StatName): number
	local base = (unit.Base :: any)[stat] :: number
	local value = Stats.apply(stat, base, self:Modifier(unit, stat))
	if stat == "ATK" then
		value *= 1 + unit.Perm.ATK
	elseif stat == "CritRate" then
		value = math.clamp(value + unit.Perm.CritRate, 0, 1)
	elseif stat == "CritDamage" then
		value += unit.Perm.CritDamage
	end
	return value
end

-- Crit chance of attacker against target, including kit bonuses (speed gaps).
function BattleSession.CritChance(self: Session, attacker: Unit, target: Unit?): number
	local chance = self:Effective(attacker, "CritRate")
	local kit = self:KitOf(attacker)
	if kit and kit.CritBonus and target then
		chance += kit.CritBonus(self, attacker, target)
	end
	return math.clamp(chance, 0, 1)
end

function BattleSession.EvasionOf(self: Session, unit: Unit): number
	local evasion = unit.Evasion
	local kit = self:KitOf(unit)
	if kit and kit.EvasionBonus then
		evasion += kit.EvasionBonus(self, unit)
	end
	return math.clamp(evasion, 0, BattleSession.EVASION_CAP)
end

-- Total damage reduction. Pierce ignores timed reduction but not permanent (barriers).
function BattleSession.DamageReduction(_self: Session, unit: Unit, pierce: boolean?): number
	local total = 0
	for _, effect in unit.Effects do
		if effect.Kind == "DamageReduction" and (not pierce or effect.Permanent) then
			total += effect.Amount
		end
	end
	return math.clamp(total, 0, BattleSession.REDUCTION_CAP)
end

function BattleSession.HasStatus(_self: Session, unit: Unit, kind: string): boolean
	for _, effect in unit.Effects do
		if effect.Kind == kind then
			return true
		end
	end
	return false
end

function BattleSession.FindEffect(_self: Session, unit: Unit, kind: string): Effect?
	for _, effect in unit.Effects do
		if effect.Kind == kind then
			return effect
		end
	end
	return nil
end

function BattleSession.HasTaunt(self: Session, unit: Unit): boolean
	if self:HasStatus(unit, "Taunt") then
		return true
	end
	local kit = self:KitOf(unit)
	return kit ~= nil and kit.IsTaunting ~= nil and kit.IsTaunting(self, unit)
end

function BattleSession.RemoveEffect(self: Session, unit: Unit, effect: Effect)
	local index = table.find(unit.Effects, effect)
	if index then
		table.remove(unit.Effects, index)
		self:_emit({ Type = "EffectExpired", Side = unit.Side, Slot = unit.Slot, Key = effect.Key })
	end
end

local function removeStatus(unit: Unit, kind: string)
	for index = #unit.Effects, 1, -1 do
		if unit.Effects[index].Kind == kind then
			table.remove(unit.Effects, index)
		end
	end
end

-- Adds an effect, or refreshes the one with the same key (longer duration, stronger amount).
local function addOrRefresh(unit: Unit, effect: Effect)
	for _, existing in unit.Effects do
		if existing.Key == effect.Key then
			existing.Turns = math.max(existing.Turns, effect.Turns)
			if math.abs(effect.Amount) > math.abs(existing.Amount) then
				existing.Amount = effect.Amount
			end
			existing.Fresh = effect.Fresh
			existing.SourceSide = effect.SourceSide or existing.SourceSide
			existing.SourceSlot = effect.SourceSlot or existing.SourceSlot
			return
		end
	end
	unit.Effects[#unit.Effects + 1] = effect
end
BattleSession.AddOrRefresh = addOrRefresh

function BattleSession.Living(self: Session, side: number): { Unit }
	local result = {}
	for _, unit in self.Teams[side].Units do
		if unit.Alive then
			table.insert(result, unit)
		end
	end
	return result
end

-- Skill availability ------------------------------------------------------------------

-- Whether a unit may pick a skill right now (energy is checked per team elsewhere).
function BattleSession.CanUse(self: Session, unit: Unit, index: number): (boolean, string?)
	local skill = unit.Skills[index]
	if not skill then
		return false, "No such skill"
	end
	local cooldown = unit.Cooldowns[skill.Id]
	if cooldown and self.Round <= cooldown then
		local left = cooldown - self.Round + 1
		return false, if left == 1 then "Cooldown: 1 round" else `Cooldown: {left} rounds`
	end
	local kit = self:KitOf(unit)
	if kit and kit.CanUse then
		local ok, reason = kit.CanUse(self, unit, index)
		if ok == false then
			return false, reason
		end
	end
	return true, nil
end

-- Round lifecycle -------------------------------------------------------------------

function BattleSession._beginRound(self: Session)
	self.Round += 1
	for _, team in self.Teams do
		local regen = 0
		for _, unit in team.Units do
			unit.DodgeRolled = false
			if unit.Alive then
				regen += unit.EnergyRegen
				local rolled = self.Rng:integer(unit.Base.SpeedMin, unit.Base.SpeedMax)
				unit.Speed = math.floor(Stats.apply("SPD", rolled, self:Modifier(unit, "SPD")) + 0.5)
				unit.Tiebreak = self.Rng:next()
			end
		end
		if team.HalfRegenRound == self.Round then
			regen = math.floor(regen / 2)
		end
		team.Energy = math.min(BattleSession.MAX_ENERGY, team.Energy + regen)
		team.Actions = nil
	end
	-- kit: speed overrides, per-round growth, auto-triggers.
	for _, team in self.Teams do
		for _, unit in team.Units do
			local kit = self:KitOf(unit)
			if unit.Alive and kit and kit.RoundStart then
				kit.RoundStart(self, unit)
			end
		end
	end
	self.Phase = "Choosing"
	self:_emit({
		Type = "RoundStart",
		Round = self.Round,
		Energy = { self.Teams[1].Energy, self.Teams[2].Energy },
	})
end

-- Burn ticks at the end of the round: % of max HP, ignores DEF, shields absorb it.
function BattleSession._tickBurns(self: Session)
	for _, team in self.Teams do
		for _, unit in team.Units do
			if unit.Alive then
				for _, effect in table.clone(unit.Effects) do
					if effect.Kind == "Burn" and unit.Alive then
						local amount = math.max(1, math.floor(unit.MaxHP * effect.Amount + 0.5))
						self:_dealDamage(unit, amount, { Type = "Burn", NoReduction = true })
					end
				end
			end
		end
	end
end

function BattleSession._endRound(self: Session)
	self:_tickBurns()
	for _, team in self.Teams do
		for _, unit in team.Units do
			local kit = self:KitOf(unit)
			if unit.Alive and kit and kit.RoundEnd then
				kit.RoundEnd(self, unit)
			end
		end
	end
	for _, team in self.Teams do
		for _, unit in team.Units do
			local kept = {}
			for _, effect in unit.Effects do
				if effect.Permanent then
					table.insert(kept, effect)
					continue
				end
				if effect.Fresh then
					effect.Fresh = false
				else
					effect.Turns -= 1
				end
				if effect.Turns > 0 then
					table.insert(kept, effect)
				else
					self:_emit({ Type = "EffectExpired", Side = unit.Side, Slot = unit.Slot, Key = effect.Key })
				end
			end
			unit.Effects = kept
		end
	end
	self:_emit({ Type = "RoundEnd", Round = self.Round })
end

function BattleSession._finish(self: Session, winner: number, reason: string)
	self.Phase = "Finished"
	self.Winner = winner
	self.EndReason = reason
	self:_emit({ Type = "BattleEnd", Winner = winner, Reason = reason })
end

-- Returns true when the battle just ended.
function BattleSession._checkWinner(self: Session): boolean
	if self.Phase == "Finished" then
		return true
	end
	local alive1 = #self:Living(1) > 0
	local alive2 = #self:Living(2) > 0
	if alive1 and alive2 then
		return false
	end
	self:_finish(if alive1 then 1 elseif alive2 then 2 else 0, "Knockout")
	return true
end

function BattleSession._hpFraction(self: Session, side: number): number
	local hp, max = 0, 0
	for _, unit in self.Teams[side].Units do
		hp += unit.HP
		max += unit.MaxHP
	end
	return if max > 0 then hp / max else 0
end

-- Actions --------------------------------------------------------------------------

function BattleSession.Validate(self: Session, side: number, actions: { [number]: Types.Action }): (boolean, string?)
	if self.Phase ~= "Choosing" then
		return false, "The battle is not waiting for actions."
	end
	if type(actions) ~= "table" then
		return false, "Actions must be a table."
	end
	local team = self.Teams[side]
	local cost = 0
	for slot, unit in team.Units do
		if unit.Alive then
			local action = actions[slot]
			if type(action) ~= "table" or type(action.Skill) ~= "number" then
				return false, `Choose a skill for {unit.Name}.`
			end
			if action.Skill == BattleSession.REST then
				continue
			end
			local skill = unit.Skills[action.Skill]
			if not skill then
				return false, `{unit.Name} has no skill {action.Skill}.`
			end
			local usable, reason = self:CanUse(unit, action.Skill)
			if not usable then
				return false, `{unit.Name} can't use {skill.Name}: {reason}.`
			end
			if action.Target ~= nil and (type(action.Target) ~= "number" or action.Target < 1 or action.Target > 3) then
				return false, "Invalid target."
			end
			cost += skill.Cost
		end
	end
	if cost > team.Energy then
		return false, `Those skills cost {cost} energy but the team has {team.Energy}.`
	end
	return true, nil
end

function BattleSession.Submit(self: Session, side: number, actions: { [number]: Types.Action }): (boolean, string?)
	local ok, err = self:Validate(side, actions)
	if not ok then
		return false, err
	end
	local copy = {}
	for slot, action in actions do
		copy[slot] = { Skill = action.Skill, Target = action.Target }
	end
	self.Teams[side].Actions = copy
	return true, nil
end

function BattleSession.IsReady(self: Session): boolean
	return self.Phase == "Choosing" and self.Teams[1].Actions ~= nil and self.Teams[2].Actions ~= nil
end

function BattleSession._firstLivingFrom(self: Session, side: number, start: number?): Unit?
	local units = self.Teams[side].Units
	local first = start or 1
	for offset = 0, 2 do
		local unit = units[((first - 1 + offset) % 3) + 1]
		if unit.Alive then
			return unit
		end
	end
	return nil
end

function BattleSession._resolveTargets(self: Session, actor: Unit, skill: Types.SkillDef, requested: number?): { Unit }
	local enemySide = 3 - actor.Side
	if skill.Target == "Self" then
		return { actor }
	elseif skill.Target == "AllAllies" then
		return self:Living(actor.Side)
	elseif skill.Target == "AllEnemies" then
		return self:Living(enemySide)
	elseif skill.Target == "Ally" then
		local ally = requested and self.Teams[actor.Side].Units[requested]
		return { if ally and ally.Alive then ally else actor }
	end
	-- A provoke on the actor beats any taunt.
	for _, effect in actor.Effects do
		if effect.Kind == "Provoke" and effect.SourceSide and effect.SourceSlot then
			local source = self.Teams[effect.SourceSide].Units[effect.SourceSlot]
			if source and source.Alive then
				return { source }
			end
		end
	end
	for _, enemy in self.Teams[enemySide].Units do
		if enemy.Alive and self:HasTaunt(enemy) then
			return { enemy }
		end
	end
	local target = self:_firstLivingFrom(enemySide, requested)
	return if target then { target } else {}
end

function BattleSession._revive(self: Session, unit: Unit, health: number)
	unit.ReviveUsed = true
	unit.Alive = true
	unit.Effects = {}
	unit.HP = math.max(1, math.floor(unit.MaxHP * health + 0.5))
	self:_emit({ Type = "Revive", Side = unit.Side, Slot = unit.Slot, HP = unit.HP })
end

local DEBUFF_KINDS: { [string]: boolean } = { Burn = true, Stun = true, Bleed = true, Provoke = true }

function BattleSession._isDebuff(_self: Session, source: Unit, recipient: Unit, spec: Types.EffectSpec): boolean
	if recipient.Side == source.Side then
		return false
	end
	if spec.Kind == "StatMod" then
		return (spec.Amount or 0) < 0
	end
	return DEBUFF_KINDS[spec.Kind] == true
end

function BattleSession._missed(self: Session, recipient: Unit, key: string, reason: string)
	self:_emit({ Type = "EffectMissed", Side = recipient.Side, Slot = recipient.Slot, Key = key, Reason = reason })
end

function BattleSession._applyBleed(self: Session, source: Unit, recipient: Unit, spec: Types.EffectSpec, key: string)
	local existing = self:FindEffect(recipient, "Bleed")
	local immune = self:FindEffect(recipient, "BleedImmune")
	local count, potency
	if existing then
		count = 1
		potency = BattleSession.BLEED_POTENCY_STEP
	else
		count = spec.Count or 2
		potency = spec.Amount or BattleSession.BLEED_POTENCY_STEP
		count = Stats.debuffTurns(count, self:Effective(source, "EFF"), self:Effective(recipient, "RES"))
	end
	if immune and immune.Count then
		local blocked = math.min(immune.Count, count)
		immune.Count -= blocked
		count -= blocked
		if immune.Count <= 0 then
			self:RemoveEffect(recipient, immune)
		end
	end
	if count <= 0 then
		self:_missed(recipient, key, "BleedImmune")
		return
	end
	local bleed: Effect
	if existing then
		existing.Amount = math.min(BattleSession.BLEED_POTENCY_CAP, existing.Amount + potency)
		existing.Count = math.min(BattleSession.BLEED_COUNT_CAP, (existing.Count or 0) + count)
		bleed = existing
	else
		bleed = {
			Kind = "Bleed",
			Key = "bleed",
			Amount = math.min(BattleSession.BLEED_POTENCY_CAP, potency),
			Count = math.min(BattleSession.BLEED_COUNT_CAP, count),
			Turns = 1,
			Debuff = true,
			Fresh = true,
			Permanent = true,
		}
		table.insert(recipient.Effects, bleed)
	end
	self:_emit({
		Type = "Effect",
		Kind = "Bleed",
		Side = recipient.Side,
		Slot = recipient.Slot,
		Key = key,
		Amount = bleed.Amount,
		Count = bleed.Count,
	})
end

function BattleSession._applyEffect(self: Session, source: Unit, recipient: Unit, spec: Types.EffectSpec, key: string)
	if spec.Kind == "Revive" then
		if not recipient.Alive and not recipient.ReviveUsed then
			self:_revive(recipient, spec.Amount or 0.3)
		end
		return
	end
	if not recipient.Alive then
		return
	end
	local hostile = recipient.Side ~= source.Side
	if self:_isDebuff(source, recipient, spec) then
		local kit = self:KitOf(recipient)
		if kit and kit.ImmuneToDebuffs and kit.ImmuneToDebuffs(self, recipient) then
			self:_missed(recipient, key, "DebuffImmune")
			return
		end
	end
	local eff = self:Effective(source, "EFF")
	local res = self:Effective(recipient, "RES")
	local chance = spec.Chance
	if spec.Kind == "Stun" then
		if self:HasStatus(recipient, "StunImmune") or self:HasStatus(recipient, "Stun") then
			self:_missed(recipient, key, "Immune")
			return
		end
		if not spec.Flat then
			chance = math.clamp((chance or 1) * math.clamp(1 + eff - res, 0.5, 1.5), 0, 1)
		end
	elseif chance and spec.Scale == "Chance" and hostile and not spec.Flat then
		chance = math.clamp(chance * math.clamp(1 + eff - res, 0.5, 1.5), 0, 1)
	end
	if chance and not self.Rng:chance(chance) then
		self:_missed(recipient, key, "Resisted")
		return
	end
	local event: Event = { Type = "Effect", Kind = spec.Kind, Side = recipient.Side, Slot = recipient.Slot, Key = key }
	local fresh = not spec.ThisRound

	if spec.Kind == "Burn" then
		local amount = spec.Amount or 0.05
		local turns = spec.Turns or 2
		if hostile then
			if spec.Scale == "Duration" then
				turns = Stats.debuffTurns(turns, eff, res)
			else
				amount = Stats.debuffPower(amount, eff, res)
			end
		end
		amount = math.min(amount, BattleSession.BURN_CAP)
		addOrRefresh(recipient, {
			Kind = "Burn",
			Key = key,
			Amount = amount,
			Turns = turns,
			Debuff = true,
			Fresh = true,
		})
		event.Amount = amount
		event.Turns = turns
		self:_emit(event)
		return
	elseif spec.Kind == "Stun" then
		addOrRefresh(recipient, {
			Kind = "Stun",
			Key = key,
			Amount = 0,
			Turns = spec.Turns or 1,
			Debuff = true,
			Fresh = true,
		})
		event.Turns = spec.Turns or 1
		self:_emit(event)
		return
	elseif spec.Kind == "EnergySteal" then
		local victim = self.Teams[recipient.Side]
		local thief = self.Teams[source.Side]
		local stolen = math.min(victim.Energy, spec.Amount or 1)
		victim.Energy -= stolen
		thief.Energy = math.min(BattleSession.MAX_ENERGY, thief.Energy + stolen)
		event.Amount = stolen
		event.SourceSide = source.Side
		self:_emit(event)
		return
	elseif spec.Kind == "Bleed" then
		self:_applyBleed(source, recipient, spec, key)
		return
	elseif spec.Kind == "StripBuffs" then
		local removed = {}
		for index = #recipient.Effects, 1, -1 do
			local effect = recipient.Effects[index]
			local strip
			if spec.Stat == "DEF" then
				strip = effect.Kind == "StatMod" and effect.Stat == "DEF" and effect.Amount > 0
			else
				strip = (effect.Kind == "StatMod" and effect.Stat == "ATK" and effect.Amount > 0)
					or (effect.Kind == "DamageReduction" and not effect.Unremovable)
			end
			if strip then
				table.insert(removed, effect.Key)
				table.remove(recipient.Effects, index)
			end
		end
		if #removed == 0 then
			return
		end
		event.Removed = removed
		self:_emit(event)
		return
	end

	if spec.Kind == "StatMod" then
		local stat = assert(spec.Stat, "StatMod needs a Stat")
		local amount = spec.Amount or 0
		local turns = spec.Turns or 1
		local debuff = amount < 0 and hostile
		if debuff then
			if spec.Scale == "Duration" then
				turns = Stats.debuffTurns(turns, eff, res)
			else
				amount = Stats.debuffPower(amount, eff, res)
			end
		end
		local existing: Effect? = nil
		for _, effect in recipient.Effects do
			if effect.Key == key then
				existing = effect
			end
		end
		if existing then
			existing.Turns = math.max(existing.Turns, turns)
			if math.abs(amount) > math.abs(existing.Amount) then
				existing.Amount = amount
			end
			existing.Fresh = fresh
		else
			local newEffect = {
				Kind = "StatMod",
				Key = key,
				Stat = stat,
				Amount = amount,
				Turns = turns,
				Debuff = debuff,
				Fresh = fresh,
			} :: any -- old solver cannot relate this literal to Effect; fields match the type above
			recipient.Effects[#recipient.Effects + 1] = newEffect
		end
		event.Stat = stat
		event.Amount = amount
		event.Turns = turns
		event.Debuff = debuff
	elseif
		spec.Kind == "Taunt"
		or spec.Kind == "Shield"
		or spec.Kind == "DamageReduction"
		or spec.Kind == "Provoke"
	then
		local turns = spec.Turns or 1
		local amount = 0
		if spec.Kind == "Shield" then
			amount = math.floor(recipient.MaxHP * (spec.Amount or 0) + 0.5)
		elseif spec.Kind == "DamageReduction" then
			amount = spec.Amount or 0
		end
		addOrRefresh(recipient, {
			Kind = spec.Kind :: any,
			Key = key,
			Amount = amount,
			Turns = turns,
			Debuff = spec.Kind == "Provoke",
			Fresh = fresh,
			SourceSide = if spec.Kind == "Provoke" then source.Side else nil,
			SourceSlot = if spec.Kind == "Provoke" then source.Slot else nil,
		})
		event.Amount = amount
		event.Turns = turns
		if spec.Kind == "Provoke" then
			event.SourceSide = source.Side
			event.SourceSlot = source.Slot
		end
	elseif spec.Kind == "Heal" then
		if recipient.NoHeal then
			return
		end
		local amount = math.floor(recipient.MaxHP * (spec.Amount or 0) + 0.5)
		local before = recipient.HP
		recipient.HP = math.min(recipient.MaxHP, recipient.HP + amount)
		event.Amount = recipient.HP - before
		event.HP = recipient.HP
	elseif spec.Kind == "Cleanse" then
		local remaining = spec.Amount or 1
		local removed = {}
		for index = #recipient.Effects, 1, -1 do
			if remaining <= 0 then
				break
			end
			local effect = recipient.Effects[index]
			if effect.Debuff then
				table.insert(removed, effect.Key)
				-- Cleanse takes bleed count, not potency.
				if effect.Kind == "Bleed" and (effect.Count or 0) > 1 then
					effect.Count = (effect.Count or 0) - 1
				else
					table.remove(recipient.Effects, index)
				end
				remaining -= 1
			end
		end
		event.Removed = removed
	elseif spec.Kind == "Energy" then
		local team = self.Teams[recipient.Side]
		team.Energy = math.clamp(team.Energy + (spec.Amount or 0), 0, BattleSession.MAX_ENERGY)
		event.Amount = spec.Amount
		event.Energy = team.Energy
	end
	self:_emit(event)
end

function BattleSession._recipients(
	self: Session,
	source: Unit,
	spec: Types.EffectSpec,
	targets: { Unit },
	attacker: Unit?
): { Unit }
	local to = spec.To or "Target"
	if to == "Self" then
		return { source }
	elseif to == "AllAllies" then
		return self:Living(source.Side)
	elseif to == "AllEnemies" then
		return self:Living(3 - source.Side)
	elseif to == "Attacker" then
		return if attacker then { attacker } else {}
	elseif to == "FallenAlly" then
		for _, unit in self.Teams[source.Side].Units do
			if not unit.Alive and not unit.ReviveUsed then
				return { unit }
			end
		end
		return {}
	end
	return targets
end

function BattleSession.HasFallenAlly(self: Session, side: number): boolean
	for _, unit in self.Teams[side].Units do
		if not unit.Alive and not unit.ReviveUsed then
			return true
		end
	end
	return false
end

function BattleSession._knockOut(self: Session, unit: Unit, reason: string?)
	unit.HP = 0
	unit.Alive = false
	unit.Effects = {}
	self:_emit({ Type = "KO", Side = unit.Side, Slot = unit.Slot, Reason = reason })
	local passive = unit.Passive
	if passive and passive.Revive and not unit.ReviveUsed then
		self:_revive(unit, passive.Revive.Health)
	end
end

export type DamageInfo = {
	Type: "Damage" | "Burn" | "Bleed",
	Source: Unit?,
	Pierce: boolean?,
	NoReduction: boolean?,
	Crit: boolean?,
	Counter: boolean?,
}

-- Applies damage already reduced by DEF: records it, then damage reduction, shields and kit HP
-- clamps. Emits one event of info.Type. Returns true if the target is still standing.
function BattleSession._dealDamage(self: Session, target: Unit, raw: number, info: DamageInfo): boolean
	target.DamageTaken[self.Round] = (target.DamageTaken[self.Round] or 0) + raw
	local amount = raw
	local reduced = 0
	if not info.NoReduction then
		local reduction = self:DamageReduction(target, info.Pierce)
		if reduction > 0 then
			amount = math.max(1, math.floor(raw * (1 - reduction) + 0.5))
			reduced = raw - amount
		end
	end
	local absorbed = 0
	for _, effect in target.Effects do
		if effect.Kind == "Shield" and effect.Amount > 0 and amount > 0 then
			local used = math.min(effect.Amount, amount)
			effect.Amount -= used
			amount -= used
			absorbed += used
		end
	end
	local newHP = math.max(0, target.HP - amount)
	local kit = self:KitOf(target)
	if kit and kit.ClampHP then
		newHP = kit.ClampHP(self, target, newHP)
	end
	target.HP = newHP
	local event: Event = {
		Type = info.Type,
		Side = target.Side,
		Slot = target.Slot,
		Amount = amount,
		Absorbed = absorbed,
		Reduced = reduced,
		HP = target.HP,
	}
	if info.Type == "Damage" and info.Source then
		event.SourceSide = info.Source.Side
		event.SourceSlot = info.Source.Slot
		event.Crit = info.Crit == true
		event.Counter = info.Counter == true
	end
	self:_emit(event)
	if target.HP <= 0 then
		self:_knockOut(target)
		return false
	end
	if kit and kit.AfterDamage then
		kit.AfterDamage(self, target)
	end
	return true
end

-- Rolls the target's evasion if this is the first attack aimed at it this round.
-- Returns false when the attack is dodged. Allies never dodge each other.
function BattleSession._attackLands(self: Session, attacker: Unit, target: Unit): boolean
	if attacker.Side == target.Side or not target.Alive or target.DodgeRolled then
		return true
	end
	target.DodgeRolled = true
	local evasion = self:EvasionOf(target)
	if evasion > 0 and self.Rng:chance(evasion) then
		self:_emit({ Type = "Dodge", Side = target.Side, Slot = target.Slot })
		return false
	end
	return true
end

-- Damage multiplier from the attacker's kit (next-round bonuses, stance bonuses).
function BattleSession._damageBonus(self: Session, attacker: Unit, skill: Types.SkillDef?): number
	local kit = self:KitOf(attacker)
	if kit and kit.DamageBonus then
		return kit.DamageBonus(self, attacker, skill)
	end
	return 1
end

-- Bleed fires once on each damaging hit taken, then loses a count.
function BattleSession._fireBleed(self: Session, target: Unit)
	local bleed = self:FindEffect(target, "Bleed")
	if not bleed or not target.Alive then
		return
	end
	local amount = math.max(1, math.floor(target.MaxHP * bleed.Amount + 0.5))
	bleed.Count = (bleed.Count or 1) - 1
	if bleed.Count <= 0 then
		self:RemoveEffect(target, bleed)
	end
	self:_dealDamage(target, amount, { Type = "Bleed" })
end

-- One hit. Returns true if it landed (not dodged).
function BattleSession._hit(
	self: Session,
	attacker: Unit,
	target: Unit,
	multiplier: number,
	options: HitOptions
): boolean
	if not (attacker.Alive and target.Alive) then
		return false
	end
	if not options.SkipDodge and not self:_attackLands(attacker, target) then
		return false
	end
	local skill = options.Skill
	local overtime = 1 + math.max(0, self.Round - BattleSession.OVERTIME_START + 1) * BattleSession.OVERTIME_STEP
	local bonus = self:_damageBonus(attacker, skill)
	local crit = false
	local amount
	if skill and skill.PercentMaxHP and not options.IsCounter then
		amount = math.max(1, math.floor(target.MaxHP * skill.PercentMaxHP * overtime * bonus + 0.5))
	else
		if not (skill and skill.NoCrit) then
			crit = self.Rng:chance(math.clamp(self:CritChance(attacker, target) + (options.CritBonus or 0), 0, 1))
		end
		local critMultiplier = if crit
			then self:Effective(attacker, "CritDamage") + (options.CritDamageBonus or 0)
			else 1
		local defense = self:Effective(target, "DEF") * (1 - (skill and skill.IgnoreDef or 0))
		amount = Stats.damage(self:Effective(attacker, "ATK"), multiplier * overtime * bonus, defense, critMultiplier)
	end

	local standing = self:_dealDamage(target, amount, {
		Type = "Damage",
		Source = attacker,
		Pierce = skill ~= nil and skill.Pierce == true,
		Crit = crit,
		Counter = options.IsCounter == true,
	})
	if not standing or attacker.Side == target.Side then
		return true
	end

	local targetKit = self:KitOf(target)
	if targetKit and targetKit.OnHitTaken then
		targetKit.OnHitTaken(self, target, attacker)
	end
	self:_fireBleed(target)
	if not target.Alive then
		return true
	end

	local passive = target.Passive
	if not passive then
		return true
	end
	if passive.OnHit and (not passive.OnHit.WhileTaunting or self:HasTaunt(target)) then
		for _, spec in passive.OnHit.Effects do
			for _, recipient in self:_recipients(target, spec, { attacker }, attacker) do
				self:_applyEffect(target, recipient, spec, `{passive.Id}:{spec.Stat or spec.Kind}`)
			end
		end
	end
	if passive.Counter and options.Single and not options.IsCounter and attacker.Alive then
		if self.Rng:chance(passive.Counter.Chance) then
			self:_emit({ Type = "Counter", Side = target.Side, Slot = target.Slot })
			local basic = target.Skills[1]
			self:_hit(
				target,
				attacker,
				(basic.Multiplier or 1) * passive.Counter.Multiplier,
				{ Single = false, IsCounter = true }
			)
		end
	end
	return true
end

-- Counter attack dealing a share of the target's max HP (ignores DEF, no crit).
function BattleSession.CounterPercent(self: Session, attacker: Unit, target: Unit, fraction: number)
	if not (attacker.Alive and target.Alive) or not self:_attackLands(attacker, target) then
		return
	end
	local amount = math.max(1, math.floor(target.MaxHP * fraction * self:_damageBonus(attacker, nil) + 0.5))
	if self:_dealDamage(target, amount, { Type = "Damage", Source = attacker, Counter = true }) then
		self:_fireBleed(target)
	end
end

-- Multi-hit move on one target. Returns true if any hit landed.
function BattleSession._combo(
	self: Session,
	unit: Unit,
	target: Unit,
	skill: Types.SkillDef,
	firstLands: boolean
): boolean
	local combo = assert(skill.Combo, "combo skill without Combo data")
	local multiplier = skill.Multiplier or 0
	local total = combo.Guaranteed + #combo.LandScale
	local landed = 0
	for hit = 1, total do
		if not (unit.Alive and target.Alive) then
			break
		end
		local extra = hit > combo.Guaranteed
		if extra then
			local chance = (self:CritChance(unit, target) + combo.CritBonus) * combo.LandScale[hit - combo.Guaranteed]
			if not self.Rng:chance(math.clamp(chance, 0, 1)) then
				break
			end
		end
		if hit == 1 and not firstLands then
			continue
		end
		if
			self:_hit(unit, target, multiplier, {
				Single = true,
				Skill = skill,
				SkipDodge = hit == 1,
				CritBonus = if extra then combo.CritBonus else 0,
				CritDamageBonus = if extra then combo.CritDamageBonus else 0,
			})
		then
			landed += 1
		end
	end
	self:_emit({ Type = "Combo", Side = unit.Side, Slot = unit.Slot, Hits = landed })
	return landed > 0
end

function BattleSession._perform(self: Session, unit: Unit, action: Types.Action)
	local team = self.Teams[unit.Side]
	if self:HasStatus(unit, "Stun") then
		-- The stun is used up; brief immunity stops stun-locking.
		removeStatus(unit, "Stun")
		addOrRefresh(unit, {
			Kind = "StunImmune",
			Key = "stun_immunity",
			Amount = 0,
			Turns = BattleSession.STUN_IMMUNITY_TURNS,
			Debuff = false,
			Fresh = true,
		})
		self:_emit({ Type = "Stunned", Side = unit.Side, Slot = unit.Slot })
		return
	end
	local kit = self:KitOf(unit)
	local index = if unit.Skills[action.Skill] then action.Skill else 1
	local skill = unit.Skills[index]
	-- kit: a forced move (auto-triggered unique) replaces the chosen one and costs nothing.
	local forced = kit and kit.ForcedSkill and kit.ForcedSkill(self, unit)
	if forced then
		skill = forced
		index = 0
	else
		if action.Skill == BattleSession.REST then
			self:_emit({ Type = "Rest", Side = unit.Side, Slot = unit.Slot })
			return
		end
		local usable, reason = self:CanUse(unit, index)
		if not usable or skill.Cost > team.Energy then
			self:_emit({
				Type = "Fallback",
				Side = unit.Side,
				Slot = unit.Slot,
				Wanted = skill.Id,
				Reason = if usable then nil else reason,
			})
			index = 1
			skill = unit.Skills[1]
			if skill.Cost > team.Energy then
				self:_emit({ Type = "Rest", Side = unit.Side, Slot = unit.Slot })
				return
			end
		end
		team.Energy -= skill.Cost
	end
	-- kit: may stop the move (sealed, cancelled) after emitting its own events.
	if kit and kit.BeforeAction and kit.BeforeAction(self, unit, skill) == false then
		return
	end
	unit.History[self.Round] = index
	if skill.Kind == "Ultimate" then
		unit.UltimateUsed = true
	end
	local targets = self:_resolveTargets(unit, skill, action.Target)
	self:_emit({
		Type = "Action",
		Side = unit.Side,
		Slot = unit.Slot,
		Skill = skill.Id,
		SkillName = skill.Name,
		Speed = skill.PrioritySpeed or unit.Speed,
		Targets = (function()
			local slots = {}
			for _, target in targets do
				table.insert(slots, { Side = target.Side, Slot = target.Slot })
			end
			return slots
		end)(),
		Energy = team.Energy,
	})
	if skill.Custom then
		assert(kit and kit.Cast, `{skill.Id} needs a kit Cast hook`)
		kit.Cast(self, unit, skill, targets)
	else
		self:_resolveSkill(unit, skill, targets)
	end
	if skill.Cooldown then
		unit.Cooldowns[skill.Id] = self.Round + skill.Cooldown
	end
	if unit.Alive and kit and kit.AfterSkill then
		kit.AfterSkill(self, unit, skill, index, targets)
	end
	unit.Uses[skill.Id] = (unit.Uses[skill.Id] or 0) + 1
end

-- Default skill resolution: dodge rolls, pre-effects, hits, follow-ups, then effects
-- on every target the attack reached.
function BattleSession._resolveSkill(self: Session, unit: Unit, skill: Types.SkillDef, targets: { Unit })
	local reached = {}
	for _, target in targets do
		local lands = self:_attackLands(unit, target)
		if lands or skill.Combo then
			if lands and skill.PreEffects then
				for _, spec in skill.PreEffects do
					self:_applyEffect(unit, target, spec, `{skill.Id}:{spec.Stat or spec.Kind}`)
				end
			end
			if skill.Combo then
				lands = self:_combo(unit, target, skill, lands)
			elseif skill.Multiplier or skill.PercentMaxHP then
				self:_hit(unit, target, skill.Multiplier or 0, {
					Single = skill.Target == "Enemy",
					Skill = skill,
					SkipDodge = true,
				})
			end
		end
		if lands then
			table.insert(reached, target)
		end
	end
	local followUp = skill.FollowUp
	if followUp and unit.Alive then
		for _, target in reached do
			if target.Alive and target.Side ~= unit.Side and target.HP / target.MaxHP < followUp.Threshold then
				self:_emit({ Type = "FollowUp", Side = unit.Side, Slot = unit.Slot })
				self:_hit(unit, target, followUp.Multiplier, { Single = false })
			end
		end
	end
	if unit.Alive then
		local effects: { Types.EffectSpec } = skill.Effects or {}
		for _, spec in effects do
			for _, recipient in self:_recipients(unit, spec, reached, nil) do
				self:_applyEffect(unit, recipient, spec, `{skill.Id}:{spec.Stat or spec.Kind}`)
			end
		end
	end
end

-- Resolves the round once both sides have submitted. Returns this round's events
-- (plus the next RoundStart, unless the battle ended).
function BattleSession.Resolve(self: Session): { Event }
	assert(self:IsReady(), "Both sides must submit before resolving")
	local queue = {}
	for _, team in self.Teams do
		local actions = assert(team.Actions, "missing submitted actions")
		for slot, unit in team.Units do
			if unit.Alive then
				local action = actions[slot]
				local skill = unit.Skills[action.Skill] or unit.Skills[1]
				local kit = self:KitOf(unit)
				local forced = kit and kit.ForcedSkill and kit.ForcedSkill(self, unit)
				if forced then
					skill = forced
				end
				table.insert(queue, {
					Unit = unit,
					Action = action,
					Speed = skill.PrioritySpeed or unit.Speed,
				})
			end
		end
	end
	table.sort(queue, function(a, b)
		if a.Speed ~= b.Speed then
			return a.Speed > b.Speed
		end
		return a.Unit.Tiebreak > b.Unit.Tiebreak
	end)
	for _, entry in queue do
		if entry.Unit.Alive then
			self:_perform(entry.Unit, entry.Action)
			if self:_checkWinner() then
				break
			end
		end
	end
	if self.Phase ~= "Finished" then
		self:_endRound()
		-- Burn (or a failed seal) can finish a team off at the end of the round.
		local knockedOut = self:_checkWinner()
		if not knockedOut and self.Round >= self.MaxRounds then
			local a, b = self:_hpFraction(1), self:_hpFraction(2)
			self:_finish(if a > b then 1 elseif b > a then 2 else 0, "RoundLimit")
		elseif not knockedOut then
			self:_beginRound()
		end
	end
	return self:TakeEvents()
end

-- Snapshot -------------------------------------------------------------------------

-- Public state. Enemy speed rolls are hidden unless viewSide is nil (server/debug).
function BattleSession.Snapshot(self: Session, viewSide: number?)
	local teams = {}
	for side, team in self.Teams do
		local units = {}
		for slot, unit in team.Units do
			local effects = {}
			for _, effect in unit.Effects do
				table.insert(effects, {
					Kind = effect.Kind,
					Key = effect.Key,
					Stat = effect.Stat,
					Amount = effect.Amount,
					Turns = effect.Turns,
					Debuff = effect.Debuff,
					Permanent = effect.Permanent,
					Count = effect.Count,
				})
			end
			local skills = {}
			for index, skill in unit.Skills do
				local usable, reason = self:CanUse(unit, index)
				skills[index] = {
					Id = skill.Id,
					Name = skill.Name,
					Kind = skill.Kind,
					Cost = skill.Cost,
					Target = skill.Target,
					Description = skill.Description,
					Usable = usable,
					Reason = reason,
				}
			end
			local kit = self:KitOf(unit)
			local status = if kit and kit.Status and unit.Alive then kit.Status(self, unit) else {}
			local evasion = self:EvasionOf(unit)
			if unit.Alive and evasion > 0 then
				table.insert(
					status,
					`Evasion {math.floor(evasion * 100 + 0.5)}% · dodge {if unit.DodgeRolled then "used" else "ready"}`
				)
			end
			local showSpeed = viewSide == nil or viewSide == side
			units[slot] = {
				Id = unit.Def.Id,
				Name = unit.Name,
				Class = unit.Class,
				Rarity = unit.Def.Rarity,
				HP = unit.HP,
				MaxHP = unit.MaxHP,
				Alive = unit.Alive,
				Speed = if showSpeed then unit.Speed else nil,
				SpeedRange = { Min = unit.Base.SpeedMin, Max = unit.Base.SpeedMax },
				EnergyRegen = unit.EnergyRegen,
				Stats = {
					ATK = self:Effective(unit, "ATK"),
					DEF = self:Effective(unit, "DEF"),
					CritRate = self:Effective(unit, "CritRate"),
					CritDamage = self:Effective(unit, "CritDamage"),
					EFF = self:Effective(unit, "EFF"),
					RES = self:Effective(unit, "RES"),
				},
				Effects = effects,
				Skills = skills,
				Passive = unit.Passive and { Name = unit.Passive.Name, Description = unit.Passive.Description } or nil,
				ReviveUsed = unit.ReviveUsed,
				Shadow = unit.IsShadow,
				Status = status,
			}
		end
		teams[side] = { Units = units, Energy = team.Energy, Submitted = team.Actions ~= nil }
	end
	return {
		Round = self.Round,
		MaxRounds = self.MaxRounds,
		MaxEnergy = BattleSession.MAX_ENERGY,
		Phase = self.Phase,
		Winner = self.Winner,
		EndReason = self.EndReason,
		Teams = teams,
	}
end

return BattleSession

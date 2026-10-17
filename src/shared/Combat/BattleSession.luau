--!strict
-- Server-authoritative 3v3 battle. Pure Luau: runs in Studio and in Lune.
--
-- Round flow: BeginRound (energy regen, speed rolls) -> both sides Submit ->
-- Resolve (speed-ordered actions) -> EndRound (effect timers) -> next BeginRound.
-- Every change is reported as an ordered event list for clients to play back.

local Types = require("../Types")
local Rng = require("../Util/Rng")
local Stats = require("./Stats")
local SkillContent = require("../Content/Skills")

local BattleSession = {}
BattleSession.__index = BattleSession

BattleSession.MAX_ENERGY = 10
BattleSession.START_ENERGY = 3
BattleSession.DEFAULT_MAX_ROUNDS = 30
-- Overtime: from this round on, all damage grows by OVERTIME_STEP per round (cumulative).
BattleSession.OVERTIME_START = 9
BattleSession.OVERTIME_STEP = 0.15

export type Effect = {
	Kind: "StatMod" | "Taunt" | "Shield",
	Key: string,
	Stat: Types.StatName?,
	Amount: number,
	Turns: number,
	Debuff: boolean,
	Fresh: boolean,
}

export type Unit = {
	Side: number,
	Slot: number,
	Def: Types.CharacterDef,
	Base: Stats.BattleStats,
	HP: number,
	MaxHP: number,
	Alive: boolean,
	Effects: { Effect },
	Speed: number,
	Tiebreak: number,
	Skills: { Types.SkillDef },
	Passive: Types.PassiveDef?,
}

export type Team = {
	Units: { Unit },
	Energy: number,
	Actions: { [number]: Types.Action }?,
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
		_events: { Event },
	},
	BattleSession
))

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
		Base = base,
		HP = base.HP,
		MaxHP = base.HP,
		Alive = true,
		Effects = {},
		Speed = 0,
		Tiebreak = 0,
		Skills = unitSkills,
		Passive = def.Passive and passives[def.Passive] or nil,
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
		_events = {},
	}, BattleSession)
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
	return Stats.apply(stat, base, self:Modifier(unit, stat))
end

function BattleSession.HasTaunt(_self: Session, unit: Unit): boolean
	for _, effect in unit.Effects do
		if effect.Kind == "Taunt" then
			return true
		end
	end
	return false
end

function BattleSession.Living(self: Session, side: number): { Unit }
	local result = {}
	for _, unit in self.Teams[side].Units do
		if unit.Alive then
			table.insert(result, unit)
		end
	end
	return result
end

-- Round lifecycle -------------------------------------------------------------------

function BattleSession._beginRound(self: Session)
	self.Round += 1
	for side, team in self.Teams do
		local regen = 0
		for _, unit in team.Units do
			if unit.Alive then
				regen += unit.Def.EnergyRegen
				local rolled = self.Rng:integer(unit.Base.SpeedMin, unit.Base.SpeedMax)
				unit.Speed = math.floor(Stats.apply("SPD", rolled, self:Modifier(unit, "SPD")) + 0.5)
				unit.Tiebreak = self.Rng:next()
			end
		end
		team.Energy = math.min(BattleSession.MAX_ENERGY, team.Energy + regen)
		team.Actions = nil
		local _ = side
	end
	self.Phase = "Choosing"
	self:_emit({
		Type = "RoundStart",
		Round = self.Round,
		Energy = { self.Teams[1].Energy, self.Teams[2].Energy },
	})
end

function BattleSession._endRound(self: Session)
	for _, team in self.Teams do
		for _, unit in team.Units do
			local kept = {}
			for _, effect in unit.Effects do
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
				return false, `Choose a skill for {unit.Def.Name}.`
			end
			local skill = unit.Skills[action.Skill]
			if not skill then
				return false, `{unit.Def.Name} has no skill {action.Skill}.`
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
	for _, enemy in self.Teams[enemySide].Units do
		if enemy.Alive and self:HasTaunt(enemy) then
			return { enemy }
		end
	end
	local target = self:_firstLivingFrom(enemySide, requested)
	return if target then { target } else {}
end

function BattleSession._applyEffect(self: Session, source: Unit, recipient: Unit, spec: Types.EffectSpec, key: string)
	if not recipient.Alive then
		return
	end
	if spec.Chance and not self.Rng:chance(spec.Chance) then
		self:_emit({ Type = "EffectMissed", Side = recipient.Side, Slot = recipient.Slot, Key = key })
		return
	end
	local event: Event = { Type = "Effect", Kind = spec.Kind, Side = recipient.Side, Slot = recipient.Slot, Key = key }

	if spec.Kind == "StatMod" then
		local stat = assert(spec.Stat, "StatMod needs a Stat")
		local amount = spec.Amount or 0
		local turns = spec.Turns or 1
		local debuff = amount < 0 and recipient.Side ~= source.Side
		if debuff then
			local eff = self:Effective(source, "EFF")
			local res = self:Effective(recipient, "RES")
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
			existing.Fresh = true
		else
			local newEffect = {
				Kind = "StatMod",
				Key = key,
				Stat = stat,
				Amount = amount,
				Turns = turns,
				Debuff = debuff,
				Fresh = true,
			} :: any -- old solver cannot relate this literal to Effect; fields match the type above
			recipient.Effects[#recipient.Effects + 1] = newEffect
		end
		event.Stat = stat
		event.Amount = amount
		event.Turns = turns
		event.Debuff = debuff
	elseif spec.Kind == "Taunt" or spec.Kind == "Shield" then
		local turns = spec.Turns or 1
		local amount = if spec.Kind == "Shield" then math.floor(recipient.MaxHP * (spec.Amount or 0) + 0.5) else 0
		local found = false
		for _, effect in recipient.Effects do
			if effect.Key == key then
				effect.Turns = math.max(effect.Turns, turns)
				effect.Amount = math.max(effect.Amount, amount)
				effect.Fresh = true
				found = true
			end
		end
		if not found then
			local newEffect: Effect = {
				Kind = if spec.Kind == "Taunt" then "Taunt" else "Shield",
				Key = key,
				Amount = amount,
				Turns = turns,
				Debuff = false,
				Fresh = true,
			}
			recipient.Effects[#recipient.Effects + 1] = newEffect
		end
		event.Amount = amount
		event.Turns = turns
	elseif spec.Kind == "Heal" then
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
				table.remove(recipient.Effects, index)
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
	end
	return targets
end

function BattleSession._knockOut(self: Session, unit: Unit)
	unit.HP = 0
	unit.Alive = false
	unit.Effects = {}
	self:_emit({ Type = "KO", Side = unit.Side, Slot = unit.Slot })
end

export type HitOptions = { Single: boolean, IsCounter: boolean? }

function BattleSession._hit(self: Session, attacker: Unit, target: Unit, multiplier: number, options: HitOptions)
	if not (attacker.Alive and target.Alive) then
		return
	end
	local crit = self.Rng:chance(self:Effective(attacker, "CritRate"))
	local critMultiplier = if crit then self:Effective(attacker, "CritDamage") else 1
	local overtime = 1 + math.max(0, self.Round - BattleSession.OVERTIME_START + 1) * BattleSession.OVERTIME_STEP
	local amount = Stats.damage(
		self:Effective(attacker, "ATK"),
		multiplier * overtime,
		self:Effective(target, "DEF"),
		critMultiplier
	)

	local absorbed = 0
	local remaining = amount
	for _, effect in target.Effects do
		if effect.Kind == "Shield" and effect.Amount > 0 and remaining > 0 then
			local used = math.min(effect.Amount, remaining)
			effect.Amount -= used
			remaining -= used
			absorbed += used
		end
	end
	target.HP = math.max(0, target.HP - remaining)
	self:_emit({
		Type = "Damage",
		Side = target.Side,
		Slot = target.Slot,
		SourceSide = attacker.Side,
		SourceSlot = attacker.Slot,
		Amount = remaining,
		Absorbed = absorbed,
		Crit = crit,
		Counter = options.IsCounter == true,
		HP = target.HP,
	})
	if target.HP <= 0 then
		self:_knockOut(target)
		return
	end

	local passive = target.Passive
	if not passive or attacker.Side == target.Side then
		return
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
end

function BattleSession._perform(self: Session, unit: Unit, action: Types.Action)
	local team = self.Teams[unit.Side]
	local skill = unit.Skills[action.Skill] or unit.Skills[1]
	if skill.Cost > team.Energy then
		self:_emit({ Type = "Fallback", Side = unit.Side, Slot = unit.Slot, Wanted = skill.Id })
		skill = unit.Skills[1]
	end
	team.Energy -= skill.Cost
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
	if skill.Multiplier then
		for _, target in targets do
			self:_hit(unit, target, skill.Multiplier, { Single = skill.Target == "Enemy" })
		end
	end
	if unit.Alive then
		local effects: { Types.EffectSpec } = skill.Effects or {}
		for _, spec in effects do
			for _, recipient in self:_recipients(unit, spec, targets, nil) do
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
	for side, team in self.Teams do
		local actions = assert(team.Actions, "missing submitted actions")
		for slot, unit in team.Units do
			if unit.Alive then
				local action = actions[slot]
				local skill = unit.Skills[action.Skill] or unit.Skills[1]
				table.insert(queue, {
					Unit = unit,
					Action = action,
					Speed = skill.PrioritySpeed or unit.Speed,
				})
			end
		end
		local _ = side
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
		if self.Round >= self.MaxRounds then
			local a, b = self:_hpFraction(1), self:_hpFraction(2)
			self:_finish(if a > b then 1 elseif b > a then 2 else 0, "RoundLimit")
		else
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
				})
			end
			local skills = {}
			for index, skill in unit.Skills do
				skills[index] = {
					Id = skill.Id,
					Name = skill.Name,
					Kind = skill.Kind,
					Cost = skill.Cost,
					Target = skill.Target,
					Description = skill.Description,
				}
			end
			local showSpeed = viewSide == nil or viewSide == side
			units[slot] = {
				Id = unit.Def.Id,
				Name = unit.Def.Name,
				Class = unit.Def.Class,
				Rarity = unit.Def.Rarity,
				HP = unit.HP,
				MaxHP = unit.MaxHP,
				Alive = unit.Alive,
				Speed = if showSpeed then unit.Speed else nil,
				SpeedRange = { Min = unit.Base.SpeedMin, Max = unit.Base.SpeedMax },
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

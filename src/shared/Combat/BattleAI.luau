--!strict
-- Heuristic AI for story NPCs, timed-out players and the balance simulator.
-- Utility classes spend energy first, damage dealers use what is left.
-- `Randomness` (0..1) makes some picks random so simulated games vary.

local Types = require("../Types")
local Rng = require("../Util/Rng")
local BattleSession = require("./BattleSession")

type Session = BattleSession.Session
type Unit = BattleSession.Unit

local BattleAI = {}

local PRIORITY: { [string]: number } = { Defense = 1, Support = 2, Disrupt = 3, Speed = 4, Attack = 5 }

export type Options = { Randomness: number? }

local function hpFraction(unit: Unit): number
	return unit.HP / unit.MaxHP
end

local function teamHpFraction(units: { Unit }): number
	local hp, max = 0, 0
	for _, unit in units do
		hp += unit.HP
		max += unit.MaxHP
	end
	return if max > 0 then hp / max else 1
end

local function hasEffectFrom(units: { Unit }, keyPrefix: string): boolean
	for _, unit in units do
		for _, effect in unit.Effects do
			if string.sub(effect.Key, 1, #keyPrefix) == keyPrefix then
				return true
			end
		end
	end
	return false
end

local function lowestHp(units: { Unit }): Unit?
	local best: Unit? = nil
	for _, unit in units do
		if not best or unit.HP < best.HP then
			best = unit
		end
	end
	return best
end

local function highestAttack(session: Session, units: { Unit }): Unit?
	local best: Unit? = nil
	local bestAtk = -1
	for _, unit in units do
		local atk = session:Effective(unit, "ATK")
		if atk > bestAtk then
			best, bestAtk = unit, atk
		end
	end
	return best
end

-- Picks a skill index for one unit given the remaining energy budget.
local function pickSkill(session: Session, unit: Unit, budget: number, allies: { Unit }, enemies: { Unit }): number
	local function can(index: number): boolean
		return unit.Skills[index].Cost <= budget
	end
	local class = unit.Def.Class
	if class == "Defense" then
		if can(3) and teamHpFraction(allies) < 0.55 then
			return 3
		end
		if can(2) and not session:HasTaunt(unit) and hpFraction(unit) > 0.35 then
			return 2
		end
	elseif class == "Support" then
		if can(3) and teamHpFraction(allies) < 0.6 then
			return 3
		end
		if can(2) and not hasEffectFrom(allies, "sup_skill") then
			return 2
		end
	elseif class == "Disrupt" then
		if can(3) and #enemies >= 2 and not hasEffectFrom(enemies, "dis_ult") then
			return 3
		end
		if can(2) then
			return 2
		end
	elseif class == "Speed" then
		if can(3) and #enemies >= 3 then
			return 3
		end
		if can(2) then
			return 2
		end
	else
		if can(3) then
			return 3
		end
		if can(2) then
			return 2
		end
	end
	return 1
end

local function pickTarget(session: Session, skill: Types.SkillDef, enemies: { Unit }): number?
	if skill.Target ~= "Enemy" then
		return nil
	end
	local lowersAttack = false
	local effects: { Types.EffectSpec } = skill.Effects or {}
	for _, spec in effects do
		if spec.Stat == "ATK" and (spec.Amount or 0) < 0 then
			lowersAttack = true
		end
	end
	local target = if lowersAttack then highestAttack(session, enemies) else lowestHp(enemies)
	return target and target.Slot
end

function BattleAI.choose(session: Session, side: number, rng: Rng.Rng, options: Options?): { [number]: Types.Action }
	local randomness = options and options.Randomness or 0
	local allies = session:Living(side)
	local enemies = session:Living(3 - side)
	local budget = session.Teams[side].Energy
	local ordered = table.clone(allies)
	table.sort(ordered, function(a, b)
		return (PRIORITY[a.Def.Class] or 9) < (PRIORITY[b.Def.Class] or 9)
	end)

	local actions: { [number]: Types.Action } = {}
	for _, unit in ordered do
		local index
		if randomness > 0 and rng:chance(randomness) then
			local affordable = {}
			for i, skill in unit.Skills do
				if skill.Cost <= budget then
					table.insert(affordable, i)
				end
			end
			index = affordable[rng:integer(1, #affordable)]
		else
			index = pickSkill(session, unit, budget, allies, enemies)
		end
		local skill = unit.Skills[index]
		budget -= skill.Cost
		local target = pickTarget(session, skill, enemies)
		if randomness > 0 and skill.Target == "Enemy" and rng:chance(randomness) then
			target = enemies[rng:integer(1, #enemies)].Slot
		end
		actions[unit.Slot] = { Skill = index, Target = target }
	end
	return actions
end

return BattleAI

--!strict
-- Turns BattleSession events into short log lines. Pure, so the server log,
-- the client battle log and tests all word things the same way.

local BattleText = {}

-- names[side][slot] = display name. viewSide decides "Your" vs "Enemy".
export type Names = { [number]: { [number]: string } }

local RELATIVE = { ATK = true, DEF = true, SPD = true, HP = true }
local STAT_LABEL = {
	ATK = "ATK",
	DEF = "DEF",
	SPD = "Speed",
	CritRate = "Crit",
	CritDamage = "Crit DMG",
	EFF = "Effectiveness",
	RES = "Resistance",
}

function BattleText.unit(names: Names, viewSide: number, side: number, slot: number): string
	local name = names[side] and names[side][slot] or `Unit {slot}`
	return if side == viewSide then `Your {name}` else `Enemy {name}`
end

function BattleText.statChange(stat: string, amount: number): string
	local sign = if amount >= 0 then "+" else ""
	local label = STAT_LABEL[stat] or stat
	if RELATIVE[stat] then
		return `{label} {sign}{math.floor(amount * 100 + 0.5)}%`
	end
	return `{label} {sign}{math.floor(amount * 100 + 0.5)}`
end

function BattleText.describe(event: { [string]: any }, names: Names, viewSide: number): string?
	local kind = event.Type
	if kind == "RoundStart" then
		return `Round {event.Round} begins.`
	elseif kind == "Action" then
		return `{BattleText.unit(names, viewSide, event.Side, event.Slot)} used {event.SkillName}.`
	elseif kind == "Damage" then
		local text = `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} took {event.Amount}`
		if event.Crit then
			text ..= " (critical)"
		end
		if event.Absorbed and event.Absorbed > 0 then
			text ..= `, {event.Absorbed} blocked by shield`
		end
		if event.Counter then
			text ..= " from a counter"
		end
		return text .. "."
	elseif kind == "Effect" then
		local who = BattleText.unit(names, viewSide, event.Side, event.Slot)
		if event.Kind == "StatMod" then
			local turns = if event.Turns == 1 then "1 turn" else `{event.Turns} turns`
			return `  {who}: {BattleText.statChange(event.Stat, event.Amount)} for {turns}.`
		elseif event.Kind == "Taunt" then
			return `  {who} is taunting.`
		elseif event.Kind == "Shield" then
			return `  {who} gained a {event.Amount} shield.`
		elseif event.Kind == "Heal" then
			return `  {who} healed {event.Amount}.`
		elseif event.Kind == "Cleanse" then
			return if event.Removed and #event.Removed > 0 then `  {who} was cleansed.` else nil
		elseif event.Kind == "Energy" then
			local team = if event.Side == viewSide then "Your team" else "Enemy team"
			local sign = if event.Amount >= 0 then "+" else ""
			return `  {team} energy {sign}{event.Amount}.`
		elseif event.Kind == "Burn" then
			return `  {who} is burning ({math.floor(event.Amount * 100 + 0.5)}% per turn).`
		elseif event.Kind == "Stun" then
			return `  {who} is stunned!`
		elseif event.Kind == "EnergySteal" then
			local thief = if event.SourceSide == viewSide then "Your team" else "The enemy"
			return `  {thief} stole {event.Amount} energy.`
		end
	elseif kind == "EffectMissed" then
		local who = BattleText.unit(names, viewSide, event.Side, event.Slot)
		return if event.Reason == "Immune" then `  {who} can't be stunned again yet.` else `  {who} resisted.`
	elseif kind == "Burn" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} took {event.Amount} burn damage.`
	elseif kind == "Stunned" then
		return `{BattleText.unit(names, viewSide, event.Side, event.Slot)} is stunned and loses its turn.`
	elseif kind == "Revive" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} revived with {event.HP} HP!`
	elseif kind == "FollowUp" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} follows up!`
	elseif kind == "Counter" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} counters!`
	elseif kind == "Fallback" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} ran out of energy and used a basic attack.`
	elseif kind == "KO" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} was knocked out!`
	elseif kind == "BattleEnd" then
		local result = if event.Winner == viewSide then "Victory!" elseif event.Winner == 0 then "Draw." else "Defeat."
		return if event.Reason == "RoundLimit" then `{result} (round limit)` else result
	end
	return nil
end

return BattleText

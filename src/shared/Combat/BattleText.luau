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
		if event.Reduced and event.Reduced > 0 then
			text ..= `, {event.Reduced} reduced`
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
		elseif event.Kind == "DamageReduction" then
			return `  {who} takes {math.floor(event.Amount * 100 + 0.5)}% less damage.`
		elseif event.Kind == "Provoke" then
			return `  {who} must target {BattleText.unit(names, viewSide, event.SourceSide, event.SourceSlot)}.`
		elseif event.Kind == "StripBuffs" then
			return `  {who} lost its buffs.`
		elseif event.Kind == "Bleed" then
			return `  {who} is bleeding ({math.floor(event.Amount * 100 + 0.5)}% x{event.Count}).`
		end
	elseif kind == "EffectMissed" then
		local who = BattleText.unit(names, viewSide, event.Side, event.Slot)
		if event.Reason == "Immune" then
			return `  {who} can't be stunned again yet.`
		elseif event.Reason == "DebuffImmune" then
			return `  {who} is immune to debuffs.`
		elseif event.Reason == "BleedImmune" then
			return `  {who} blocked the bleed.`
		end
		return `  {who} resisted.`
	elseif kind == "Burn" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} took {event.Amount} burn damage.`
	elseif kind == "Bleed" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} took {event.Amount} bleed damage.`
	elseif kind == "Dodge" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} dodged!`
	elseif kind == "Combo" then
		return `  {event.Hits}-hit combo!`
	elseif kind == "Transform" then
		local who = BattleText.unit(names, viewSide, event.Side, event.Slot)
		return if event.Form == "Devil" then `{who} broke the seal and transformed!` else `{who} transformed!`
	elseif kind == "Shadow" then
		local owner = if event.Side == viewSide then "Your" else "Enemy"
		return `  {owner} {event.Name} rises!`
	elseif kind == "Kit" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)}: {event.Text}`
	elseif kind == "Cancelled" then
		return `{BattleText.unit(names, viewSide, event.Side, event.Slot)}'s {event.SkillName} was cancelled (+{event.Refund} energy back).`
	elseif kind == "Sealed" then
		return `{BattleText.unit(names, viewSide, event.Side, event.Slot)} is sealed and can't act.`
	elseif kind == "Rest" then
		return `{BattleText.unit(names, viewSide, event.Side, event.Slot)} rests.`
	elseif kind == "Stunned" then
		return `{BattleText.unit(names, viewSide, event.Side, event.Slot)} is stunned and loses its turn.`
	elseif kind == "Revive" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} revived with {event.HP} HP!`
	elseif kind == "FollowUp" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} follows up!`
	elseif kind == "Counter" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} counters!`
	elseif kind == "Fallback" then
		local who = BattleText.unit(names, viewSide, event.Side, event.Slot)
		if event.Reason then
			return `  {who} couldn't use that move ({event.Reason}) and used a basic attack.`
		end
		return `  {who} ran out of energy and used a basic attack.`
	elseif kind == "KO" then
		return `  {BattleText.unit(names, viewSide, event.Side, event.Slot)} was knocked out!`
	elseif kind == "BattleEnd" then
		local result = if event.Winner == viewSide then "Victory!" elseif event.Winner == 0 then "Draw." else "Defeat."
		return if event.Reason == "RoundLimit" then `{result} (round limit)` else result
	end
	return nil
end

return BattleText

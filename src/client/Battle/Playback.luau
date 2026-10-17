--!nonstrict
-- Plays a round's server events back in order with placeholder feedback.
-- The server already decided everything; this only shows it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local BattleText = require(ReplicatedStorage.Shared.Combat.BattleText)
local State = require(script.Parent.BattleState)
local ArenaView = require(script.Parent.ArenaView)

local Playback = {}

local function log(event)
	local line = BattleText.describe(event, State.names(), State.side())
	if line then
		State.addLog(line)
	end
end

local function showBanner(text: string, seconds: number)
	State.banner(text)
	task.delay(seconds, function()
		if State.banner() == text then
			State.banner(nil)
		end
	end)
end

local function play(event)
	local kind = event.Type
	log(event)
	if kind == "RoundStart" then
		showBanner(`Round {event.Round}`, 1.2)
		task.wait(0.5)
	elseif kind == "Action" then
		local first = event.Targets and event.Targets[1]
		local hostile = first and first.Side ~= event.Side
		if hostile then
			ArenaView.lunge(event.Side, event.Slot, first.Side, first.Slot)
		else
			ArenaView.flash(event.Side, event.Slot, Theme.Accent)
			task.wait(0.25)
		end
	elseif kind == "Damage" then
		State.setHp(event.Side, event.Slot, event.HP)
		ArenaView.flash(event.Side, event.Slot, Theme.Bad)
		local text = if event.Crit then `{event.Amount}!` else tostring(event.Amount)
		ArenaView.float(
			event.Side,
			event.Slot,
			text,
			if event.Crit then Theme.Accent else Color3.new(1, 1, 1),
			event.Crit
		)
		if event.Absorbed and event.Absorbed > 0 then
			ArenaView.float(event.Side, event.Slot, `({event.Absorbed} blocked)`, Theme.Stat.DEF)
		end
		task.wait(0.3)
	elseif kind == "Effect" then
		if event.Kind == "Heal" then
			State.setHp(event.Side, event.Slot, event.HP)
			ArenaView.float(event.Side, event.Slot, `+{event.Amount}`, Theme.Good)
		elseif event.Kind == "StatMod" then
			local color = if event.Amount >= 0 then Theme.Good else Theme.Bad
			ArenaView.float(event.Side, event.Slot, BattleText.statChange(event.Stat, event.Amount), color)
		elseif event.Kind == "Taunt" then
			ArenaView.float(event.Side, event.Slot, "TAUNT", Theme.Accent)
		elseif event.Kind == "Shield" then
			ArenaView.float(event.Side, event.Slot, `Shield {event.Amount}`, Theme.Stat.DEF)
		elseif event.Kind == "Energy" then
			ArenaView.float(
				event.Side,
				event.Slot,
				`Energy {if event.Amount >= 0 then "+" else ""}{event.Amount}`,
				Theme.Stat.SPD
			)
		end
		task.wait(0.15)
	elseif kind == "Counter" then
		ArenaView.float(event.Side, event.Slot, "COUNTER", Theme.Accent, true)
		task.wait(0.2)
	elseif kind == "KO" then
		State.setHp(event.Side, event.Slot, 0)
		ArenaView.knockOut(event.Side, event.Slot)
		ArenaView.float(event.Side, event.Slot, "K.O.", Theme.Bad, true)
		task.wait(0.5)
	elseif kind == "BattleEnd" then
		local won = event.Winner == State.side()
		showBanner(if won then "VICTORY" elseif event.Winner == 0 then "DRAW" else "DEFEAT", 2.5)
		task.wait(0.8)
	end
end

-- Plays events, then calls done(). Yields.
function Playback.Run(events: { any })
	for _, event in events do
		local ok, err = pcall(play, event)
		if not ok then
			warn(`[Playback] {event.Type}: {err}`)
		end
	end
end

-- Logs events without animating (used for the opening RoundStart).
function Playback.LogOnly(events: { any })
	for _, event in events do
		log(event)
	end
end

return Playback

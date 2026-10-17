--!nonstrict
-- Reactive battle state shared by the battle UI, arena view and playback.
-- Sources are Vide signals: call with no argument to read, with one to write.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local source = vide.source

local State = {
	battleId = source(nil :: string?),
	side = source(1),
	center = source(CFrame.identity),
	snapshot = source(nil :: any),
	-- "Idle" | "Choosing" | "Waiting" | "Playback" | "Finished"
	phase = source("Idle"),
	-- { Side, Slot } of the unit shown in the info panel.
	selected = source(nil :: any),
	-- { Slot, Skill, Kind } while picking a target for a skill.
	targeting = source(nil :: any),
	-- [slot] = { Skill, Target }
	actions = source({} :: { [number]: any }),
	deadline = source(0),
	-- Shown HP during playback: hp[side][slot].
	hp = source({} :: { [number]: { [number]: number } }),
	log = source({} :: { string }),
	banner = source(nil :: string?),
	hint = source(""),
	result = source(nil :: any),
}

function State.unit(side: number, slot: number)
	local snapshot = State.snapshot()
	return snapshot and snapshot.Teams[side].Units[slot]
end

function State.names()
	local names = {}
	local snapshot = State.snapshot()
	if snapshot then
		for side, team in snapshot.Teams do
			names[side] = {}
			for slot, unit in team.Units do
				names[side][slot] = unit.Name
			end
		end
	end
	return names
end

function State.addLog(line: string)
	local lines = table.clone(State.log())
	table.insert(lines, line)
	while #lines > 40 do
		table.remove(lines, 1)
	end
	State.log(lines)
end

function State.syncHp()
	local snapshot = State.snapshot()
	local hp = {}
	if snapshot then
		for side, team in snapshot.Teams do
			hp[side] = {}
			for slot, unit in team.Units do
				hp[side][slot] = unit.HP
			end
		end
	end
	State.hp(hp)
end

function State.setHp(side: number, slot: number, value: number)
	local hp = table.clone(State.hp())
	hp[side] = table.clone(hp[side] or {})
	hp[side][slot] = value
	State.hp(hp)
end

-- Total energy the currently planned moves will cost.
function State.plannedCost(): number
	local snapshot = State.snapshot()
	if not snapshot then
		return 0
	end
	local total = 0
	for slot, action in State.actions() do
		local unit = snapshot.Teams[State.side()].Units[slot]
		if unit and unit.Alive and unit.Skills[action.Skill] then
			total += unit.Skills[action.Skill].Cost
		end
	end
	return total
end

function State.allChosen(): boolean
	local snapshot = State.snapshot()
	if not snapshot then
		return false
	end
	for slot, unit in snapshot.Teams[State.side()].Units do
		if unit.Alive and not State.actions()[slot] then
			return false
		end
	end
	return true
end

function State.reset()
	State.battleId(nil)
	State.snapshot(nil)
	State.phase("Idle")
	State.selected(nil)
	State.targeting(nil)
	State.actions({})
	State.hp({})
	State.log({})
	State.banner(nil)
	State.hint("")
	State.result(nil)
end

return State

--!nonstrict
-- Battle flow on the client: listens for the server, handles clicks
-- (unit -> skill -> target), submits moves and drives playback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local State = require(script.Parent.BattleState)
local ArenaView = require(script.Parent.ArenaView)
local Playback = require(script.Parent.Playback)
local BattleHud = require(script.Parent.BattleHud)

local BattleController = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local submitRemote = remotes:WaitForChild("SubmitActions")
local leaveRemote = remotes:WaitForChild("LeaveBattle")

local ownSide = function()
	return State.side()
end

local function firstOpenUnit(): number?
	local snapshot = State.snapshot()
	if not snapshot then
		return nil
	end
	for slot, unit in snapshot.Teams[ownSide()].Units do
		if unit.Alive and not State.actions()[slot] then
			return slot
		end
	end
	return nil
end

-- After a move is set, jump to the next unit that still needs one.
local function advance()
	local slot = firstOpenUnit()
	if slot then
		State.selected({ Side = ownSide(), Slot = slot })
		State.hint("Choose a skill for the highlighted unit.")
	else
		State.hint("All moves set. Press Confirm turn.")
	end
end

local function setAction(slot: number, action)
	local actions = table.clone(State.actions())
	actions[slot] = action
	State.actions(actions)
	State.targeting(nil)
	advance()
end

local function startChoosing()
	State.actions({})
	State.targeting(nil)
	State.phase("Choosing")
	advance()
end

function BattleController.chooseSkill(slot: number, index: number)
	local unit = State.unit(ownSide(), slot)
	local skill = unit and unit.Skills[index]
	if not skill or not unit.Alive or State.phase() ~= "Choosing" then
		return
	end
	local snapshot = State.snapshot()
	local energy = snapshot.Teams[ownSide()].Energy
	local existing = State.actions()[slot]
	local otherCost = State.plannedCost() - (if existing then unit.Skills[existing.Skill].Cost else 0)
	if otherCost + skill.Cost > energy then
		State.hint(`Not enough energy for {skill.Name} ({skill.Cost}). Change another move or pick a cheaper skill.`)
		return
	end
	if skill.Target == "Enemy" or skill.Target == "Ally" then
		State.targeting({ Slot = slot, Skill = index, Kind = skill.Target })
		State.hint(
			if skill.Target == "Enemy" then `Click an enemy for {skill.Name}.` else `Click an ally for {skill.Name}.`
		)
	else
		setAction(slot, { Skill = index })
	end
end

local function onUnitClicked(side: number, slot: number)
	local targeting = State.targeting()
	local unit = State.unit(side, slot)
	if targeting and State.phase() == "Choosing" then
		local wanted = if targeting.Kind == "Enemy" then 3 - ownSide() else ownSide()
		if side == wanted and unit and unit.Alive then
			setAction(targeting.Slot, { Skill = targeting.Skill, Target = slot })
			return
		end
	end
	State.targeting(nil)
	State.selected({ Side = side, Slot = slot })
end

function BattleController.confirm()
	if State.phase() ~= "Choosing" then
		return
	end
	if not State.allChosen() then
		State.hint("Choose a move for every unit first.")
		return
	end
	local list = {}
	for slot, action in State.actions() do
		table.insert(list, { Slot = slot, Skill = action.Skill, Target = action.Target })
	end
	State.phase("Waiting")
	local ok, response = pcall(submitRemote.InvokeServer, submitRemote, State.battleId(), list)
	if ok and type(response) == "table" and response.success then
		State.hint("Moves locked in.")
	else
		State.phase("Choosing")
		State.hint(
			if ok and type(response) == "table" then response.message or "Could not submit." else "Could not submit."
		)
	end
end

function BattleController.clear()
	if State.phase() == "Choosing" then
		State.actions({})
		State.targeting(nil)
		advance()
	end
end

-- Prototype menus (summon, team select, PvP queue) would cover the battle screen.
local hiddenGuis: { ScreenGui } = {}
local OWN_GUIS = { BattleHud = true, MainHud = true }

local function hidePrototypeMenus()
	local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled and not OWN_GUIS[gui.Name] and not gui.Name:find("Iris") then
			gui.Enabled = false
			table.insert(hiddenGuis, gui)
		end
	end
end

local function restorePrototypeMenus()
	for _, gui in hiddenGuis do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(hiddenGuis)
end

local function exitBattle()
	ArenaView.Unmount()
	State.reset()
	restorePrototypeMenus()
end

function BattleController.leave()
	local id = State.battleId()
	if id then
		pcall(leaveRemote.InvokeServer, leaveRemote, id)
	end
	exitBattle()
end

local function onStarted(payload)
	State.reset()
	State.battleId(payload.BattleId)
	State.side(payload.Side)
	State.center(payload.Center)
	State.snapshot(payload.Snapshot)
	State.deadline(payload.Deadline)
	State.syncHp()
	Playback.LogOnly(payload.Events)
	State.phase("Playback")
	hidePrototypeMenus()
	ArenaView.Mount(onUnitClicked)
	startChoosing()
end

local function onUpdate(payload)
	if payload.BattleId ~= State.battleId() then
		return
	end
	State.phase("Playback")
	State.targeting(nil)
	State.hint("")
	Playback.Run(payload.Events)
	if payload.BattleId ~= State.battleId() then
		return
	end
	State.snapshot(payload.Snapshot)
	State.syncHp()
	State.deadline(payload.Deadline)
	if payload.Result then
		State.result(payload.Result)
		State.phase("Finished")
	else
		startChoosing()
	end
end

function BattleController.Start()
	vide.root(function()
		BattleHud.create(BattleController)
	end)
	remotes:WaitForChild("BattleStarted").OnClientEvent:Connect(function(payload)
		task.spawn(onStarted, payload)
	end)
	remotes:WaitForChild("BattleUpdate").OnClientEvent:Connect(function(payload)
		task.spawn(onUpdate, payload)
	end)
	-- The server closes an arena (cleanup, disconnect): leave the battle view too.
	local arenas = workspace:WaitForChild("Arenas")
	arenas.ChildRemoved:Connect(function(child)
		if State.battleId() and child.Name == `Arena_{State.battleId()}` then
			exitBattle()
		end
	end)
end

return BattleController

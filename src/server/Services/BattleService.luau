--!nonstrict
-- Runs battles on this server: creates the session and arena, collects actions,
-- enforces the turn timer, resolves rounds and pays rewards.
-- Phase 2: practice battles against the AI. Phase 6 adds PvP on reserved servers
-- and Phase 7 adds story battles, both through StartBattle.
--
-- Remotes:
--   StartPracticeBattle() -> { success, message }
--   SubmitActions(battleId, actions) -> { success, message }
--   LeaveBattle(battleId) -> { success }
--   BattleStarted (server -> client): { BattleId, Side, Center, Snapshot, Events, Deadline }
--   BattleUpdate (server -> client):  { BattleId, Snapshot, Events, Deadline, Result? }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local t = require(ReplicatedStorage.Packages.t)
local Characters = require(Shared.Content.Characters)
local Items = require(Shared.Content.Items)
local Loadout = require(Shared.Rules.Loadout)
local BattleRewardRules = require(Shared.Rules.BattleRewardRules)
local BattleSession = require(Shared.Combat.BattleSession)
local BattleAI = require(Shared.Combat.BattleAI)
local Rng = require(Shared.Util.Rng)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local ArenaService = require(script.Parent.ArenaService)

local BattleService = {}

BattleService.TURN_SECONDS = 30
-- Extra time per event so clients can finish playing the round back.
BattleService.PLAYBACK_SECONDS_PER_EVENT = 0.3
BattleService.MAX_PLAYBACK_SECONDS = 14
BattleService.CLEANUP_SECONDS = 90

local PRACTICE_ENEMIES = { "TrainingSpeed", "TrainingDisrupt", "TrainingDefense" }
local STARTER_TEAM = {
	{ Id = "TrainingAttack", Items = {} },
	{ Id = "TrainingDefense", Items = {} },
	{ Id = "TrainingSupport", Items = {} },
}

local battles: { [string]: any } = {}
local battleOf: { [Player]: string } = {}
local seedSource = Random.new()
local nextId = 0

local started = Net.event("BattleStarted")
local updated = Net.event("BattleUpdate")

local function now(): number
	return workspace:GetServerTimeNow()
end

local function playerTeam(player: Player)
	local data = ProfileService.Get(player)
	if data and Loadout.validateTeam(data.Team, data.Characters, data.Items, Characters, Items) then
		return Loadout.toBattleTeam(data.Team, Characters, Items)
	end
	return Loadout.toBattleTeam(STARTER_TEAM, Characters, Items)
end

local function arenaTeams(session)
	local teams = {}
	for side, team in session.Teams do
		teams[side] = {}
		for slot, unit in team.Units do
			teams[side][slot] = { Name = unit.Def.Name, Class = unit.Def.Class }
		end
	end
	return teams
end

local function sideOf(battle, player: Player): number?
	for side, occupant in battle.Players do
		if occupant == player then
			return side
		end
	end
	return nil
end

local function send(battle, events, result)
	for side, player in battle.Players do
		if player.Parent then
			updated:FireClient(player, {
				BattleId = battle.Id,
				Snapshot = battle.Session:Snapshot(side),
				Events = events,
				Deadline = battle.Deadline,
				Result = result and result[side],
			})
		end
	end
end

local function setDeadline(battle, eventCount: number)
	local playback = math.min(BattleService.MAX_PLAYBACK_SECONDS, eventCount * BattleService.PLAYBACK_SECONDS_PER_EVENT)
	battle.Deadline = now() + playback + BattleService.TURN_SECONDS
	battle.Turn += 1
	local turn = battle.Turn
	task.delay(battle.Deadline - now() + 1, function()
		if battles[battle.Id] == battle and battle.Turn == turn then
			BattleService._timeout(battle)
		end
	end)
end

local function aiSubmit(battle)
	for side = 1, 2 do
		if not battle.Players[side] and battle.Session.Phase == "Choosing" then
			assert(
				battle.Session:Submit(side, BattleAI.choose(battle.Session, side, battle.AiRng, { Randomness = 0.1 }))
			)
		end
	end
end

local function finish(battle)
	local session = battle.Session
	local result = {}
	for side, player in battle.Players do
		local outcome = if session.Winner == side then "Win" elseif session.Winner == 0 then "Draw" else "Loss"
		local amount = BattleRewardRules.gemsForOutcome(outcome) or 0
		local claimed = EconomyService.ClaimReward(player, `{battle.Id}_{side}`, amount, outcome)
		result[side] = { Outcome = outcome, Gems = if claimed then amount else 0 }
	end
	battle.Result = result
	task.delay(BattleService.CLEANUP_SECONDS, function()
		if battles[battle.Id] == battle then
			BattleService._close(battle)
		end
	end)
	return result
end

local function resolveIfReady(battle)
	local session = battle.Session
	if battle.Resolving or not session:IsReady() then
		return
	end
	battle.Resolving = true
	local events = session:Resolve()
	local result = nil
	if session.Phase == "Finished" then
		result = finish(battle)
		battle.Turn += 1
	else
		aiSubmit(battle)
		setDeadline(battle, #events)
	end
	battle.Resolving = false
	send(battle, events, result)
end

-- A player ran out of time: the AI picks their moves (no randomness) and the round resolves.
function BattleService._timeout(battle)
	local session = battle.Session
	if session.Phase ~= "Choosing" then
		return
	end
	for side in battle.Players do
		if not session.Teams[side].Actions then
			assert(session:Submit(side, BattleAI.choose(session, side, battle.AiRng, { Randomness = 0 })))
		end
	end
	resolveIfReady(battle)
end

function BattleService._close(battle)
	battles[battle.Id] = nil
	for _, player in battle.Players do
		if battleOf[player] == battle.Id then
			battleOf[player] = nil
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and player.Parent then
			root.Anchored = false
			local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
			local target = if spawn then spawn.CFrame + Vector3.new(0, 4, 0) else CFrame.new(0, 6, 0)
			character:PivotTo(target)
		end
	end
	ArenaService.Destroy(battle.Arena)
end

-- teams = { [side] = TeamLoadout }, players = { [side] = Player? } (nil side = AI).
function BattleService.StartBattle(kind: string, teams, players: { [number]: Player })
	nextId += 1
	local id = `{kind}_{os.time()}_{nextId}`
	local seed = seedSource:NextInteger(1, 2 ^ 30)
	local session = BattleSession.new({ Seed = seed, Teams = teams })
	local battle = {
		Id = id,
		Kind = kind,
		Session = session,
		Players = players,
		AiRng = Rng.new(seed + 7),
		Turn = 0,
		Deadline = 0,
		Resolving = false,
		Result = nil,
	}
	battle.Arena = ArenaService.Create(id, arenaTeams(session))
	battles[id] = battle
	local openingEvents = session:TakeEvents()
	aiSubmit(battle)
	setDeadline(battle, 0)

	for side, player in players do
		battleOf[player] = id
		local stand = ArenaService.StandCFrame(battle.Arena.Center, side)
		pcall(player.RequestStreamAroundAsync, player, stand.Position)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			character:PivotTo(stand)
			root.Anchored = true
		end
		started:FireClient(player, {
			BattleId = id,
			Side = side,
			Center = battle.Arena.Center,
			Snapshot = session:Snapshot(side),
			Events = openingEvents,
			Deadline = battle.Deadline,
		})
	end
	return battle
end

-- Sent as a gap-free list: Roblox drops array entries after a nil when a slot is knocked out.
local actionsShape = t.array(t.strictInterface({ Slot = t.integer, Skill = t.integer, Target = t.optional(t.integer) }))

function BattleService.Submit(player: Player, battleId: string, actions)
	local battle = battles[battleId]
	if not battle or battleOf[player] ~= battleId then
		return { success = false, message = "You are not in that battle." }
	end
	local side = sideOf(battle, player)
	if not side then
		return { success = false, message = "You are not in that battle." }
	end
	if battle.Session.Teams[side].Actions then
		return { success = false, message = "Moves already locked in." }
	end
	if #actions > 3 then
		return { success = false, message = "Invalid moves." }
	end
	local bySlot = {}
	for _, entry in actions do
		bySlot[entry.Slot] = { Skill = entry.Skill, Target = entry.Target }
	end
	local ok, err = battle.Session:Submit(side, bySlot)
	if not ok then
		return { success = false, message = err }
	end
	task.defer(resolveIfReady, battle)
	return { success = true }
end

function BattleService.Leave(player: Player, battleId: string)
	local battle = battles[battleId]
	if not battle or battleOf[player] ~= battleId then
		return { success = false }
	end
	-- Leaving mid-battle forfeits with no reward; after the end it just closes.
	BattleService._close(battle)
	return { success = true }
end

function BattleService.Start()
	Net.handle("StartPracticeBattle", { Rate = 0.5, Burst = 2 }, function(player)
		if battleOf[player] then
			return { success = false, message = "You are already in a battle." }
		end
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			return { success = false, message = "Wait for your character to load." }
		end
		local enemy = {}
		for index, id in PRACTICE_ENEMIES do
			enemy[index] = { Character = Characters[id], Items = {} }
		end
		BattleService.StartBattle("Practice", { playerTeam(player), enemy }, { [1] = player })
		return { success = true }
	end)
	Net.handle("SubmitActions", {
		Rate = 2,
		Burst = 4,
		Validate = function(battleId, actions)
			return type(battleId) == "string" and #battleId < 80 and actionsShape(actions)
		end,
	}, BattleService.Submit)
	Net.handle("LeaveBattle", { Rate = 1, Burst = 2, Validate = t.string }, BattleService.Leave)
	Players.PlayerRemoving:Connect(function(player)
		local id = battleOf[player]
		local battle = id and battles[id]
		if battle then
			BattleService._close(battle)
		end
	end)
end

return BattleService

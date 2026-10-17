--!nonstrict
-- Practice battle against a fixed AI team, using the Phase 1 BattleSession.
-- Speaks the prototype Combat Lab's protocol so that menu works until Phase 2:
--   "Attack" = the unit's basic skill, "Action2" = its signature skill.
-- Ultimates are in the engine but need the Phase 2 battle UI to be picked.

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

local PveService = {}

local ENEMY_TEAM = { "TrainingSpeed", "TrainingDisrupt", "TrainingDefense" }
local LOG_LINES = 18
local KIND_TO_SKILL = { Attack = 1, Action2 = 2 }

local battles: { [Player]: any } = {}
local seedSource = Random.new()
local nextBattle = 0

local function prefix(side: number): string
	return if side == 1 then "P" else "E"
end

local function unitName(session, side, slot): string
	return `{prefix(side)}{slot} {session.Teams[side].Units[slot].Def.Name}`
end

local function addLog(state, line: string)
	table.insert(state.Log, 1, line)
	while #state.Log > LOG_LINES do
		table.remove(state.Log)
	end
end

local function describe(state, events)
	local session = state.Session
	for _, event in events do
		if event.Type == "RoundStart" then
			local rolls = {}
			for slot, unit in session.Teams[1].Units do
				if unit.Alive then
					table.insert(rolls, `P{slot} {unit.Speed}`)
				end
			end
			addLog(
				state,
				`Round {event.Round}: your speed rolls {table.concat(rolls, " · ")} | energy {event.Energy[1]}/{BattleSession.MAX_ENERGY}`
			)
		elseif event.Type == "Action" then
			addLog(state, `{unitName(session, event.Side, event.Slot)} used {event.SkillName}.`)
		elseif event.Type == "Damage" then
			local extra = if event.Crit then " CRIT" else ""
			if event.Absorbed > 0 then
				extra ..= ` ({event.Absorbed} shielded)`
			end
			local verb = if event.Counter then "countered" else "hit"
			addLog(state, `  {verb} {prefix(event.Side)}{event.Slot} for {event.Amount}{extra}.`)
		elseif event.Type == "Effect" then
			if event.Kind == "StatMod" then
				local sign = if event.Amount >= 0 then "+" else ""
				local amount = if event.Stat == "ATK"
						or event.Stat == "DEF"
						or event.Stat == "SPD"
					then `{math.floor(event.Amount * 100 + 0.5)}%`
					else `{math.floor(event.Amount * 100 + 0.5)} pts`
				addLog(state, `  {prefix(event.Side)}{event.Slot} {event.Stat} {sign}{amount} for {event.Turns} turns.`)
			elseif event.Kind == "Taunt" then
				addLog(state, `  {prefix(event.Side)}{event.Slot} is taunting.`)
			elseif event.Kind == "Shield" then
				addLog(state, `  {prefix(event.Side)}{event.Slot} shielded for {event.Amount}.`)
			elseif event.Kind == "Heal" then
				addLog(state, `  {prefix(event.Side)}{event.Slot} healed {event.Amount}.`)
			elseif event.Kind == "Energy" then
				addLog(
					state,
					`  {if event.Side == 1 then "Your" else "Enemy"} energy {if event.Amount >= 0 then "+" else ""}{event.Amount}.`
				)
			end
		elseif event.Type == "Fallback" then
			addLog(state, `  {unitName(session, event.Side, event.Slot)} lacked energy and used a basic attack.`)
		elseif event.Type == "KO" then
			addLog(state, `  {unitName(session, event.Side, event.Slot)} was knocked out!`)
		elseif event.Type == "BattleEnd" then
			local text = if event.Winner == 1 then "VICTORY!" elseif event.Winner == 2 then "DEFEAT." else "DRAW."
			addLog(state, if event.Reason == "RoundLimit" then `{text} Round limit reached.` else text)
		end
	end
end

local function grantReward(state)
	local session = state.Session
	if session.Phase ~= "Finished" or state.RewardGranted then
		return
	end
	local outcome = if session.Winner == 1 then "Win" elseif session.Winner == 2 then "Loss" else "Draw"
	local amount = BattleRewardRules.gemsForOutcome(outcome)
	local ok = EconomyService.ClaimReward(state.Player, state.BattleId, amount, outcome)
	state.RewardGranted = ok
	state.RewardAmount = if ok then amount else 0
	if ok then
		addLog(state, `Battle reward: +{amount} gems.`)
	end
end

local function newBattle(player: Player)
	nextBattle += 1
	local data = ProfileService.Get(player)
	local ready = data ~= nil and Loadout.validateTeam(data.Team, data.Characters, data.Items, Characters, Items)
	local playerTeam
	if ready then
		playerTeam = Loadout.toBattleTeam(data.Team, Characters, Items)
	else
		playerTeam = Loadout.toBattleTeam({
			{ Id = "TrainingAttack", Items = {} },
			{ Id = "TrainingDefense", Items = {} },
			{ Id = "TrainingSupport", Items = {} },
		}, Characters, Items)
	end
	local enemyTeam = {}
	for index, id in ENEMY_TEAM do
		enemyTeam[index] = { Character = Characters[id], Items = {} }
	end
	local seed = seedSource:NextInteger(1, 2 ^ 30)
	local session = BattleSession.new({ Seed = seed, Teams = { playerTeam, enemyTeam } })
	local state = {
		Player = player,
		BattleId = string.format("PvE_%d_%d_%d", player.UserId, os.time(), nextBattle),
		Session = session,
		AiRng = Rng.new(seed + 1),
		Chosen = {},
		Targets = { 1, 1, 1 },
		Log = {},
		Ready = ready == true,
		Status = if ready then "Saved 3v3 team loaded." else "Profile loading — using the starter team.",
		RewardGranted = false,
		RewardAmount = 0,
	}
	describe(state, session:TakeEvents())
	return state
end

local function classEffects(session, unit)
	local flags = { AttackBuff = false, DefenseBuff = false, SupportBuff = false, Haste = false, Disrupted = false }
	for _, effect in unit.Effects do
		if effect.Debuff then
			flags.Disrupted = true
		elseif effect.Kind == "Taunt" or effect.Kind == "Shield" or (effect.Stat == "DEF" and effect.Amount > 0) then
			flags.DefenseBuff = true
		elseif effect.Stat == "SPD" and effect.Amount > 0 then
			flags.Haste = true
		elseif string.sub(effect.Key, 1, 4) == "sup_" then
			flags.SupportBuff = true
		elseif effect.Stat == "ATK" or effect.Stat == "CritRate" then
			flags.AttackBuff = true
		end
	end
	local _ = session
	return flags
end

local function unitSnapshot(state, side, slot)
	local session = state.Session
	local unit = session.Teams[side].Units[slot]
	return {
		Id = unit.Def.Id,
		Name = unit.Def.Name,
		Class = unit.Def.Class,
		HP = unit.HP,
		Stats = { MaxHealth = unit.MaxHP },
		Target = if side == 1 then state.Targets[slot] else 1,
		Action = state.Chosen[slot] or (if unit.Alive then "Choose Action" else "KO"),
		Action2Cost = unit.Skills[2].Cost,
		Skills = (function()
			local list = {}
			for index, skill in unit.Skills do
				list[index] =
					{ Name = skill.Name, Cost = skill.Cost, Kind = skill.Kind, Description = skill.Description }
			end
			return list
		end)(),
		Effects = classEffects(session, unit),
	}
end

local function regen(session, side)
	local total = 0
	for _, unit in session.Teams[side].Units do
		if unit.Alive then
			total += unit.Def.EnergyRegen
		end
	end
	return total
end

local function snapshot(state)
	local session = state.Session
	local playerTeam, enemyTeam = {}, {}
	local allChosen = true
	for slot = 1, 3 do
		playerTeam[slot] = unitSnapshot(state, 1, slot)
		enemyTeam[slot] = unitSnapshot(state, 2, slot)
		if session.Teams[1].Units[slot].Alive and not state.Chosen[slot] then
			allChosen = false
		end
	end
	local finished = session.Phase == "Finished"
	return {
		PlayerTeam = playerTeam,
		EnemyTeam = enemyTeam,
		CanBattle = not finished,
		CanResolve = not finished and allChosen,
		TeamStatus = state.Status,
		Energy = {
			Player = session.Teams[1].Energy,
			Enemy = session.Teams[2].Energy,
			Max = BattleSession.MAX_ENERGY,
			PlayerGain = regen(session, 1),
			EnemyGain = regen(session, 2),
		},
		Battle = {
			TurnNumber = session.Round,
			Log = table.clone(state.Log),
			Finished = finished,
			Winner = if session.Winner == 1
				then "Player"
				elseif session.Winner == 2 then "Enemy"
				elseif finished then "Draw"
				else nil,
			RewardGranted = state.RewardGranted,
			RewardAmount = state.RewardAmount,
		},
	}
end

local function chosenCost(state, exceptSlot)
	local units = state.Session.Teams[1].Units
	local total = 0
	for slot, kind in state.Chosen do
		if slot ~= exceptSlot and units[slot].Alive then
			total += units[slot].Skills[KIND_TO_SKILL[kind]].Cost
		end
	end
	return total
end

local function cycleTarget(state, slot, direction)
	local enemies = state.Session.Teams[2].Units
	local current = state.Targets[slot]
	for step = 1, 3 do
		local candidate = ((current - 1 + direction * step) % 3) + 1
		if enemies[candidate].Alive then
			state.Targets[slot] = candidate
			return
		end
	end
end

local function resolve(state)
	local session = state.Session
	local actions = {}
	for slot, unit in session.Teams[1].Units do
		if unit.Alive then
			local kind = state.Chosen[slot]
			if not kind then
				addLog(state, "Choose an action for every living character.")
				return
			end
			actions[slot] = { Skill = KIND_TO_SKILL[kind], Target = state.Targets[slot] }
		end
	end
	local ok, err = session:Submit(1, actions)
	if not ok then
		addLog(state, err)
		return
	end
	assert(session:Submit(2, BattleAI.choose(session, 2, state.AiRng, { Randomness = 0.1 })))
	describe(state, session:Resolve())
	state.Chosen = {}
	for slot = 1, 3 do
		if not session.Teams[2].Units[state.Targets[slot]].Alive then
			cycleTarget(state, slot, 1)
		end
	end
	grantReward(state)
end

local requestShape = t.strictInterface({
	Action = t.literal("ResetBattle", "SelectTarget", "SetAction", "ResolveTurn"),
	Side = t.optional(t.literal("Player")),
	Slot = t.optional(t.integer),
	Direction = t.optional(t.literal(-1, 1)),
	Kind = t.optional(t.literal("Attack", "Action2")),
})

local function handle(player: Player, request)
	local state = battles[player]
	if not state or (type(request) == "table" and request.Action == "ResetBattle") then
		state = newBattle(player)
		battles[player] = state
	end
	if type(request) ~= "table" then
		return snapshot(state)
	end
	local session = state.Session
	local slot = request.Slot
	local validSlot = type(slot) == "number" and slot >= 1 and slot <= 3
	if request.Action == "SelectTarget" and validSlot then
		cycleTarget(state, slot, request.Direction or 1)
	elseif request.Action == "SetAction" and validSlot and session.Phase ~= "Finished" then
		local unit = session.Teams[1].Units[slot]
		if unit.Alive then
			local cost = unit.Skills[KIND_TO_SKILL[request.Kind]].Cost
			if chosenCost(state, slot) + cost > session.Teams[1].Energy then
				addLog(state, `P{slot} needs more energy for {unit.Skills[KIND_TO_SKILL[request.Kind]].Name} ({cost}).`)
			else
				state.Chosen[slot] = request.Kind
			end
		end
	elseif request.Action == "ResolveTurn" and session.Phase ~= "Finished" then
		resolve(state)
	end
	return snapshot(state)
end

function PveService.Start()
	Net.handle("GetCombatLabSnapshot", {
		Rate = 10,
		Burst = 20,
		Validate = function(request)
			return request == nil or requestShape(request)
		end,
	}, handle)
	Players.PlayerRemoving:Connect(function(player)
		battles[player] = nil
	end)
end

return PveService

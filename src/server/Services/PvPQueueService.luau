--!nonstrict
-- Same-server queue carried over from the prototype: pairs players and validates
-- both saved teams. Phase 6 replaces it with cross-server MemoryStore matchmaking
-- and reserved battle servers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Content.Characters)
local Items = require(Shared.Content.Items)
local Loadout = require(Shared.Rules.Loadout)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)

local PvPQueueService = {}

local waiting = {}
local queued: { [Player]: boolean } = {}
local matches = {}
local nextMatch = 0

local queueUpdated = Net.event("PvPQueueUpdated")
local matchFound = Net.event("PvPMatchFound")

local function validatedTeam(player: Player)
	local data = ProfileService.Get(player)
	if not data then
		return nil, "Your profile is still loading."
	end
	local ok, message = Loadout.validateTeam(data.Team, data.Characters, data.Items, Characters, Items)
	if not ok then
		return nil, message
	end
	local ids = {}
	for index, slot in data.Team do
		ids[index] = slot.Id
	end
	return ids
end

local function displayTeam(ids)
	local result = {}
	for index, id in ids or {} do
		result[index] = { Id = id, Name = Characters[id].Name, Class = Characters[id].Class }
	end
	return result
end

local function removeFromQueue(player: Player)
	queued[player] = nil
	for index = #waiting, 1, -1 do
		local entry = waiting[index]
		if entry.Player == player or not entry.Player.Parent then
			queued[entry.Player] = nil
			table.remove(waiting, index)
		end
	end
end

local function publicSnapshot(player: Player, message: string?)
	local opponentId = player:GetAttribute("PvPOpponentUserId")
	local opponent = opponentId and Players:GetPlayerByUserId(opponentId)
	return {
		InQueue = queued[player] == true,
		QueueSize = #waiting,
		Status = message or (if queued[player] then "Searching this server for an opponent..." else "Not in queue."),
		MatchId = player:GetAttribute("PvPMatchId"),
		OpponentName = opponent and opponent.Name or nil,
		OpponentUserId = opponentId,
	}
end

local function matchSnapshot(player: Player)
	local id = player:GetAttribute("PvPMatchId")
	local match = id and matches[id]
	if not match then
		return { Ready = false, Status = "No active PvP match." }
	end
	local isA = match.PlayerA == player.UserId
	local opponentId = if isA then match.PlayerB else match.PlayerA
	local opponent = Players:GetPlayerByUserId(opponentId)
	return {
		Ready = true,
		MatchId = match.Id,
		Status = match.Status,
		OwnTeam = displayTeam(if isA then match.TeamA else match.TeamB),
		OpponentTeam = displayTeam(if isA then match.TeamB else match.TeamA),
		OpponentName = opponent and opponent.Name or "Opponent",
	}
end

local function publish(message: string)
	for _, player in Players:GetPlayers() do
		queueUpdated:FireClient(player, publicSnapshot(player, message))
	end
end

local function createMatch(a: Player, b: Player, teamA, teamB)
	nextMatch += 1
	local id = string.format("LocalPvP_%d_%d", os.time(), nextMatch)
	matches[id] =
		{ Id = id, PlayerA = a.UserId, PlayerB = b.UserId, TeamA = teamA, TeamB = teamB, Status = "TeamsValidated" }
	queued[a], queued[b] = nil, nil
	a:SetAttribute("PvPMatchId", id)
	b:SetAttribute("PvPMatchId", id)
	a:SetAttribute("PvPOpponentUserId", b.UserId)
	b:SetAttribute("PvPOpponentUserId", a.UserId)
	local status = "Opponent found. Both saved teams were validated. Live PvP battles arrive in Phase 6."
	matchFound:FireClient(a, { MatchId = id, OpponentName = b.Name, OpponentUserId = b.UserId, Status = status })
	matchFound:FireClient(b, { MatchId = id, OpponentName = a.Name, OpponentUserId = a.UserId, Status = status })
	publish(status)
end

function PvPQueueService.Start()
	Net.handle("GetPvPQueueSnapshot", { Rate = 2 }, function(player)
		return publicSnapshot(player)
	end)
	Net.handle("GetPvPMatchSnapshot", { Rate = 2 }, matchSnapshot)
	Net.handle("JoinPvPQueue", { Rate = 1, Burst = 3 }, function(player)
		if player:GetAttribute("PvPMatchId") then
			return publicSnapshot(player, "You already have a PvP match.")
		end
		local team, reason = validatedTeam(player)
		if not team then
			return publicSnapshot(player, reason)
		end
		if queued[player] then
			return publicSnapshot(player, "You are already searching.")
		end
		queued[player] = true
		table.insert(waiting, { Player = player, Team = team })
		if #waiting >= 2 then
			local first = table.remove(waiting, 1)
			local second = table.remove(waiting, 1)
			if first.Player.Parent and second.Player.Parent then
				createMatch(first.Player, second.Player, first.Team, second.Team)
			end
		end
		publish("Searching this server for an opponent...")
		return publicSnapshot(player)
	end)
	Net.handle("LeavePvPQueue", { Rate = 1, Burst = 3 }, function(player)
		removeFromQueue(player)
		publish("You left the PvP queue.")
		return publicSnapshot(player, "You left the PvP queue.")
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeFromQueue(player)
		local id = player:GetAttribute("PvPMatchId")
		if id then
			matches[id] = nil
		end
	end)
end

return PvPQueueService

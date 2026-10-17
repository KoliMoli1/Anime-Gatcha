local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local core = RS:WaitForChild('AnimeCombatCore')
local remotes = core:WaitForChild('Remotes')
local getSnapshot = remotes:WaitForChild('GetPvPQueueSnapshot')
local getMatch = remotes:WaitForChild('GetPvPMatchSnapshot')
local joinQueue = remotes:WaitForChild('JoinPvPQueue')
local leaveQueue = remotes:WaitForChild('LeavePvPQueue')
local queueUpdated = remotes:WaitForChild('PvPQueueUpdated')
local matchFound = remotes:WaitForChild('PvPMatchFound')
local profiles = require(game.ServerScriptService.Services:WaitForChild('ProfileRegistry'))
local definitions = require(core.Shared:WaitForChild('CharacterDefinitions'))
local waiting = {}
local queued = {}
local matches = {}
local nextMatch = 0

local function removeFromQueue(player)
    queued[player] = nil
    for i = #waiting, 1, -1 do
        local entry = waiting[i]
        local entryPlayer = type(entry) == 'table' and entry.Player or entry
        if entryPlayer == player or not entryPlayer or not entryPlayer.Parent then
            table.remove(waiting, i)
            if entryPlayer then queued[entryPlayer] = nil end
        end
    end
end

local function validatedTeam(player)
    local profile = profiles[player]
    if not profile then return nil, 'Your profile is still loading.' end
    if type(profile.SelectedTeam) ~= 'table' then return nil, 'Select a team first.' end
    local result, seen = {}, {}
    for i = 1, 3 do
        local id = profile.SelectedTeam[i]
        if type(id) ~= 'string' or not definitions[id] then return nil, 'Save all three team slots first.' end
        if seen[id] then return nil, 'Duplicate characters are not allowed.' end
        if not profile.OwnedCharacters[id] then return nil, 'Your saved team contains an unowned character.' end
        seen[id] = true
        result[i] = id
    end
    return result
end

local function displayTeam(ids)
    local result = {}
    for i, id in ipairs(ids or {}) do
        result[i] = {Id = id, Name = definitions[id].DisplayName, Class = (function() for class in pairs(definitions[id].Classes or {}) do return class end return 'Unknown' end)()}
    end
    return result
end

local function publicSnapshot(player, message)
    local matchId = player:GetAttribute('PvPMatchId')
    local opponentId = player:GetAttribute('PvPOpponentUserId')
    local opponent = opponentId and Players:GetPlayerByUserId(opponentId)
    return {
        InQueue = queued[player] == true,
        QueueSize = #waiting,
        Status = message or (queued[player] and 'Searching this server for an opponent...' or 'Not in queue.'),
        MatchId = matchId,
        OpponentName = opponent and opponent.Name or nil,
        OpponentUserId = opponentId,
    }
end

local function matchSnapshot(player)
    local id = player:GetAttribute('PvPMatchId')
    local match = id and matches[id]
    if not match then return {Ready = false, Status = 'No active PvP match.'} end
    local isA = match.PlayerA == player.UserId
    local opponentId = isA and match.PlayerB or match.PlayerA
    local own = isA and match.TeamA or match.TeamB
    local enemy = isA and match.TeamB or match.TeamA
    local opponent = Players:GetPlayerByUserId(opponentId)
    return {
        Ready = true,
        MatchId = match.Id,
        Status = match.Status,
        OwnTeam = displayTeam(own),
        OpponentTeam = displayTeam(enemy),
        OpponentName = opponent and opponent.Name or 'Opponent',
        PlayerAUserId = match.PlayerA,
        PlayerBUserId = match.PlayerB,
    }
end

local function publish(message)
    for _, player in ipairs(Players:GetPlayers()) do queueUpdated:FireClient(player, publicSnapshot(player, message)) end
end

local function createMatch(a, b, teamA, teamB)
    nextMatch += 1
    local id = string.format('LocalPvP_%d_%d', os.time(), nextMatch)
    local record = {Id = id, PlayerA = a.UserId, PlayerB = b.UserId, TeamA = teamA, TeamB = teamB, Status = 'TeamsValidated', CreatedAt = os.time()}
    matches[id] = record
    queued[a], queued[b] = nil, nil
    a:SetAttribute('PvPMatchId', id); b:SetAttribute('PvPMatchId', id)
    a:SetAttribute('PvPOpponentUserId', b.UserId); b:SetAttribute('PvPOpponentUserId', a.UserId)
    local status = 'Opponent found. Both saved teams were validated.'
    matchFound:FireClient(a, {MatchId = id, OpponentName = b.Name, OpponentUserId = b.UserId, Status = status})
    matchFound:FireClient(b, {MatchId = id, OpponentName = a.Name, OpponentUserId = a.UserId, Status = status})
    publish(status)
end

getSnapshot.OnServerInvoke = function(player) return publicSnapshot(player) end
getMatch.OnServerInvoke = function(player) return matchSnapshot(player) end

joinQueue.OnServerInvoke = function(player)
    if player:GetAttribute('PvPMatchId') then return publicSnapshot(player, 'You already have a PvP match.') end
    local team, reason = validatedTeam(player)
    if not team then return publicSnapshot(player, reason) end
    if queued[player] then return publicSnapshot(player, 'You are already searching.') end
    queued[player] = true
    table.insert(waiting, {Player = player, Team = team})
    if #waiting >= 2 then
        local first = table.remove(waiting, 1)
        local second = table.remove(waiting, 1)
        if first.Player.Parent and second.Player.Parent then createMatch(first.Player, second.Player, first.Team, second.Team) end
    end
    publish('Searching this server for an opponent...')
    return publicSnapshot(player)
end

leaveQueue.OnServerInvoke = function(player)
    removeFromQueue(player)
    publish('You left the PvP queue.')
    return publicSnapshot(player, 'You left the PvP queue.')
end

Players.PlayerRemoving:Connect(function(player)
    removeFromQueue(player)
    local matchId = player:GetAttribute('PvPMatchId')
    if matchId then matches[matchId] = nil end
end)

print('[PvPQueueServer] Same-server PvP queue and validated match handoff online.')

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local core = ReplicatedStorage:WaitForChild("AnimeCombatCore")
local remotes = core:WaitForChild("Remotes")
local definitions = require(core.Shared:WaitForChild("CharacterDefinitions"))
local BattleEngine = require(core.Shared:WaitForChild("BattleEngine"))
local profiles = require(script.Parent:WaitForChild("Services"):WaitForChild("ProfileRegistry"))
local combatRemote = remotes:WaitForChild("GetCombatLabSnapshot")
local grantBattleReward = script.Parent:WaitForChild("Services"):WaitForChild("GrantBattleReward")

local states = {}
local lastRequestAt = {}
local REQUEST_COOLDOWN = 0.04
local MAX_ROUNDS = 20
local nextBattle = 0

local ids = {}
for id in pairs(definitions) do table.insert(ids, id) end
table.sort(ids)

local function fallbackTeam()
    return { ids[1], ids[2] or ids[1], ids[3] or ids[1] }
end

local function loadRoster(player)
    local profile = profiles[player]
    if not profile or type(profile.SelectedTeam) ~= "table" then
        return fallbackTeam(), false, "TEAM SELECT REQUIRED: save three characters."
    end
    local result, seen = {}, {}
    for i = 1, 3 do
        local id = profile.SelectedTeam[i]
        if type(id) ~= "string" or not definitions[id] or seen[id] or not profile.OwnedCharacters[id] then
            return fallbackTeam(), false, "Saved team is invalid."
        end
        seen[id] = true
        result[i] = id
    end
    return result, true, "Saved 3v3 team loaded."
end

local function zeroes()
    return { 0, 0, 0 }
end

local function createState(player)
    nextBattle += 1
    local playerTeam, ready, status = loadRoster(player)
    local enemyTeam = {
        definitions.TrainingSpeed and "TrainingSpeed" or (ids[3] or ids[1]),
        definitions.TrainingDisrupt and "TrainingDisrupt" or ids[1],
        definitions.TrainingDefense and "TrainingDefense" or (ids[2] or ids[1]),
    }
    local state = {
        player = player,
        battleId = string.format("PvE_%d_%d_%d", player.UserId, os.time(), nextBattle),
        playerTeam = playerTeam,
        enemyTeam = enemyTeam,
        playerHealth = {},
        enemyHealth = {},
        playerEnergy = 0,
        enemyEnergy = 0,
        playerGain = BattleEngine.TeamEnergyGain(playerTeam, definitions),
        enemyGain = BattleEngine.TeamEnergyGain(enemyTeam, definitions),
        playerActions = {},
        enemyActions = {},
        playerTargets = { 1, 2, 3 },
        enemyTargets = { 1, 2, 3 },
        playerAttackBoost = zeroes(),
        enemyAttackBoost = zeroes(),
        playerGuard = zeroes(),
        enemyGuard = zeroes(),
        playerHaste = zeroes(),
        enemyHaste = zeroes(),
        playerDisruptedTurns = 0,
        enemyDisruptedTurns = 0,
        playerTeamCrit = 0,
        enemyTeamCrit = 0,
        playerTauntSlot = nil,
        enemyTauntSlot = nil,
        playerTauntTurns = 0,
        enemyTauntTurns = 0,
        turn = 1,
        log = {},
        ready = ready,
        status = status,
        finished = false,
        winner = nil,
        rewardGranted = false,
        rewardAmount = 0,
    }
    for i = 1, 3 do
        state.playerHealth[i] = definitions[playerTeam[i]].BaseStats.MaxHealth
        state.enemyHealth[i] = definitions[enemyTeam[i]].BaseStats.MaxHealth
    end
    state.log[1] = ready and "Battle ready. Speed determines action order." or status
    return state
end

local function getState(player)
    states[player] = states[player] or createState(player)
    return states[player]
end

local function addLog(state, message)
    table.insert(state.log, 1, message)
    while #state.log > 18 do table.remove(state.log) end
end

local function validSlot(slot)
    return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= 3
end

local function cycleTarget(current, direction, health)
    direction = direction == -1 and -1 or 1
    for step = 1, 3 do
        local candidate = ((current - 1 + direction * step) % 3) + 1
        if (health[candidate] or 0) > 0 then return candidate end
    end
    return current
end

local function chooseEnemyActions(state)
    for slot, id in ipairs(state.enemyTeam) do
        if state.enemyHealth[slot] <= 0 then
            state.enemyActions[slot] = "Skip"
        else
            local class = BattleEngine.ClassOf(definitions[id])
            local cost = BattleEngine.Action2Cost(definitions[id])
            local useAction2 = false
            if state.enemyEnergy >= cost then
                if class == "Defense" then useAction2 = state.enemyTauntTurns <= 0
                elseif class == "Support" then useAction2 = state.enemyTeamCrit <= 0
                elseif class == "Attack" then useAction2 = state.enemyAttackBoost[slot] <= 0 and state.turn % 2 == 0
                elseif class == "Disrupt" then useAction2 = state.playerDisruptedTurns <= 0
                elseif class == "Speed" then useAction2 = state.enemyHaste[slot] <= 0
                end
            end
            state.enemyActions[slot] = useAction2 and "Action2" or "Attack"
        end
    end
end

local function applyAction2(state, side, slot, definition)
    local class = BattleEngine.ClassOf(definition)
    if side == "Player" then
        if class == "Attack" then
            state.playerAttackBoost[slot] = 1
            addLog(state, "P"..slot.." prepared Damage Up for its next attack.")
        elseif class == "Defense" then
            state.playerGuard[slot] = 2
            state.playerTauntSlot, state.playerTauntTurns = slot, 2
            addLog(state, "P"..slot.." used Taunt and Guard.")
        elseif class == "Support" then
            state.playerTeamCrit = 2
            addLog(state, "P"..slot.." raised allied critical chance for the next round.")
        elseif class == "Disrupt" then
            state.enemyDisruptedTurns = 2
            addLog(state, "P"..slot.." used Sabotage: enemy Speed and Defense reduced for 2 rounds.")
        elseif class == "Speed" then
            state.playerHaste[slot] = 2
            addLog(state, "P"..slot.." used Overclock: Speed and critical chance raised for 2 rounds.")
        end
    else
        if class == "Attack" then
            state.enemyAttackBoost[slot] = 1
            addLog(state, "E"..slot.." prepared Damage Up for its next attack.")
        elseif class == "Defense" then
            state.enemyGuard[slot] = 2
            state.enemyTauntSlot, state.enemyTauntTurns = slot, 2
            addLog(state, "E"..slot.." used Taunt and Guard.")
        elseif class == "Support" then
            state.enemyTeamCrit = 2
            addLog(state, "E"..slot.." raised enemy critical chance for the next round.")
        elseif class == "Disrupt" then
            state.playerDisruptedTurns = 2
            addLog(state, "E"..slot.." used Sabotage: allied Speed and Defense reduced for 2 rounds.")
        elseif class == "Speed" then
            state.enemyHaste[slot] = 2
            addLog(state, "E"..slot.." used Overclock: Speed and critical chance raised for 2 rounds.")
        end
    end
end

local function decrement(values)
    for i = 1, 3 do values[i] = math.max(0, (values[i] or 0) - 1) end
end

local function grantFinishedReward(state)
    if state.rewardGranted or not state.finished or not state.player then return end
    local outcome = state.winner == "Player" and "Win" or state.winner == "Enemy" and "Loss" or "Draw"
    local ok, amount = grantBattleReward:Invoke(state.player, outcome, state.battleId)
    state.rewardGranted = ok == true
    state.rewardAmount = ok and amount or 0
    if ok then addLog(state, string.format("Battle reward: +%d coins.", amount)) end
end

local function finishIfNeeded(state)
    local winner = BattleEngine.Winner(state.playerHealth, state.enemyHealth)
    if winner then
        state.finished = true
        state.winner = winner
        addLog(state, winner == "Player" and "VICTORY! Enemy team defeated." or winner == "Enemy" and "DEFEAT. Your team was defeated." or "DRAW. Both teams were defeated.")
        grantFinishedReward(state)
        return true
    end
    return false
end

local function executeAttack(state, action)
    local isPlayer = action.Side == "Player"
    local ownHealth = isPlayer and state.playerHealth or state.enemyHealth
    if ownHealth[action.Slot] <= 0 then return end

    local ownTeam = isPlayer and state.playerTeam or state.enemyTeam
    local targetTeam = isPlayer and state.enemyTeam or state.playerTeam
    local targetHealth = isPlayer and state.enemyHealth or state.playerHealth
    local requested = isPlayer and state.playerTargets[action.Slot] or state.enemyTargets[action.Slot]
    local tauntSlot = isPlayer and (state.enemyTauntTurns > 0 and state.enemyTauntSlot or nil) or (state.playerTauntTurns > 0 and state.playerTauntSlot or nil)
    local targetSlot = BattleEngine.ResolveTarget(requested, targetHealth, tauntSlot)
    if not targetSlot then return end

    local boosts = isPlayer and state.playerAttackBoost or state.enemyAttackBoost
    local guards = isPlayer and state.enemyGuard or state.playerGuard
    local teamCrit = isPlayer and state.playerTeamCrit or state.enemyTeamCrit
    local haste = isPlayer and state.playerHaste or state.enemyHaste
    local targetDisrupted = isPlayer and state.enemyDisruptedTurns or state.playerDisruptedTurns
    local result = BattleEngine.CalculateAttack(definitions[ownTeam[action.Slot]], definitions[targetTeam[targetSlot]], {
        AttackMultiplier = boosts[action.Slot] > 0 and 1.5 or 1,
        DefenseMultiplier = (guards[targetSlot] > 0 and 1.5 or 1) * (targetDisrupted > 0 and 0.75 or 1),
        CritBonus = (teamCrit > 0 and 0.20 or 0) + (haste[action.Slot] > 0 and 0.25 or 0),
    })
    targetHealth[targetSlot] = math.max(0, targetHealth[targetSlot] - result.Amount)
    boosts[action.Slot] = 0
    local prefix = isPlayer and "P" or "E"
    local targetPrefix = isPlayer and "E" or "P"
    addLog(state, string.format("%s%d %s attacked %s%d for %d%s.", prefix, action.Slot, definitions[ownTeam[action.Slot]].DisplayName, targetPrefix, targetSlot, result.Amount, result.IsCritical and " CRIT" or ""))
end

local function resolveTurn(state)
    if not state.ready or state.finished then return end
    for i = 1, 3 do
        if state.playerHealth[i] > 0 and not state.playerActions[i] then
            addLog(state, "Choose an action for every living character.")
            return
        end
        if state.playerHealth[i] <= 0 then state.playerActions[i] = "Skip" end
    end

    chooseEnemyActions(state)
    local queue = BattleEngine.BuildActionQueue(state.playerTeam, state.enemyTeam, state.playerHealth, state.enemyHealth, state.playerActions, state.enemyActions, definitions, {
        Player = {Haste = state.playerHaste, Disrupted = state.playerDisruptedTurns},
        Enemy = {Haste = state.enemyHaste, Disrupted = state.enemyDisruptedTurns},
    })
    for _, action in ipairs(queue) do
        if state.finished then break end
        if action.Kind == "Action2" then
            local definition = definitions[action.CharacterId]
            local cost = BattleEngine.Action2Cost(definition)
            local energy = action.Side == "Player" and state.playerEnergy or state.enemyEnergy
            if energy >= cost then
                if action.Side == "Player" then state.playerEnergy -= cost else state.enemyEnergy -= cost end
                applyAction2(state, action.Side, action.Slot, definition)
            else
                executeAttack(state, action)
            end
        elseif action.Kind == "Attack" then
            executeAttack(state, action)
        end
        finishIfNeeded(state)
    end

    if not state.finished then
        state.playerEnergy = math.clamp(state.playerEnergy + state.playerGain, 0, BattleEngine.MAX_ENERGY)
        state.enemyEnergy = math.clamp(state.enemyEnergy + state.enemyGain, 0, BattleEngine.MAX_ENERGY)
        decrement(state.playerGuard)
        decrement(state.enemyGuard)
        decrement(state.playerHaste)
        decrement(state.enemyHaste)
        state.playerDisruptedTurns = math.max(0, state.playerDisruptedTurns - 1)
        state.enemyDisruptedTurns = math.max(0, state.enemyDisruptedTurns - 1)
        state.playerTeamCrit = math.max(0, state.playerTeamCrit - 1)
        state.enemyTeamCrit = math.max(0, state.enemyTeamCrit - 1)
        state.playerTauntTurns = math.max(0, state.playerTauntTurns - 1)
        state.enemyTauntTurns = math.max(0, state.enemyTauntTurns - 1)
        if state.playerTauntTurns == 0 then state.playerTauntSlot = nil end
        if state.enemyTauntTurns == 0 then state.enemyTauntSlot = nil end
        state.turn += 1
        if state.turn > MAX_ROUNDS then
            state.finished, state.winner = true, "Draw"
            addLog(state, "DRAW. Maximum round limit reached.")
            grantFinishedReward(state)
        else
            addLog(state, string.format("Round %d ready. Energy P %d/%d | E %d/%d.", state.turn, state.playerEnergy, BattleEngine.MAX_ENERGY, state.enemyEnergy, BattleEngine.MAX_ENERGY))
        end
    end
    state.playerActions = {}
    state.enemyActions = {}
end

local function unitSnapshot(state, side, slot)
    local isPlayer = side == "Player"
    local team = isPlayer and state.playerTeam or state.enemyTeam
    local health = isPlayer and state.playerHealth or state.enemyHealth
    local actions = isPlayer and state.playerActions or state.enemyActions
    local targets = isPlayer and state.playerTargets or state.enemyTargets
    local boosts = isPlayer and state.playerAttackBoost or state.enemyAttackBoost
    local guards = isPlayer and state.playerGuard or state.enemyGuard
    local definition = definitions[team[slot]]
    return {
        Id = team[slot],
        Name = definition.DisplayName,
        Class = BattleEngine.ClassOf(definition),
        Stats = table.clone(definition.BaseStats),
        HP = health[slot],
        Action = actions[slot] or (health[slot] > 0 and "Choose Action" or "KO"),
        Target = targets[slot],
        Action2Cost = BattleEngine.Action2Cost(definition),
        Effects = {
            AttackBuff = boosts[slot] > 0,
            DefenseBuff = guards[slot] > 0,
            SupportBuff = (isPlayer and state.playerTeamCrit or state.enemyTeamCrit) > 0,
            Haste = (isPlayer and state.playerHaste or state.enemyHaste)[slot] > 0,
            Disrupted = (isPlayer and state.playerDisruptedTurns or state.enemyDisruptedTurns) > 0,
        },
    }
end

local function snapshot(state)
    local playerTeam, enemyTeam = {}, {}
    local allChosen = true
    for i = 1, 3 do
        playerTeam[i] = unitSnapshot(state, "Player", i)
        enemyTeam[i] = unitSnapshot(state, "Enemy", i)
        if state.playerHealth[i] > 0 and not state.playerActions[i] then allChosen = false end
    end
    local characters = {}
    for id, definition in pairs(definitions) do
        characters[id] = { DisplayName = definition.DisplayName, Rarity = definition.Rarity, Class = BattleEngine.ClassOf(definition), Stats = table.clone(definition.BaseStats) }
    end
    return {
        Characters = characters,
        PlayerTeam = playerTeam,
        EnemyTeam = enemyTeam,
        CanBattle = state.ready and not state.finished,
        CanResolve = state.ready and not state.finished and allChosen,
        TeamStatus = state.status,
        Energy = { Player = state.playerEnergy, Enemy = state.enemyEnergy, Max = BattleEngine.MAX_ENERGY, PlayerGain = state.playerGain, EnemyGain = state.enemyGain },
        Battle = { TurnNumber = state.turn, Log = table.clone(state.log), Finished = state.finished, Winner = state.winner, RewardGranted = state.rewardGranted, RewardAmount = state.rewardAmount },
    }
end

combatRemote.OnServerInvoke = function(player, request)
    local now = os.clock()
    if now - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
        return snapshot(getState(player))
    end
    lastRequestAt[player] = now
    local state = getState(player)
    if type(request) ~= "table" then return snapshot(state) end

    if request.Action == "ResetBattle" then
        states[player] = createState(player)
        state = states[player]
    elseif request.Action == "SelectTarget" and request.Side == "Player" and validSlot(request.Slot) then
        state.playerTargets[request.Slot] = cycleTarget(state.playerTargets[request.Slot], request.Direction, state.enemyHealth)
    elseif request.Action == "SetAction" and request.Side == "Player" and validSlot(request.Slot) and (request.Kind == "Attack" or request.Kind == "Action2") then
        if state.playerHealth[request.Slot] > 0 and not state.finished then
            if request.Kind == "Action2" and state.playerEnergy < BattleEngine.Action2Cost(definitions[state.playerTeam[request.Slot]]) then
                addLog(state, string.format("P%d needs more energy for Action 2.", request.Slot))
            else
                state.playerActions[request.Slot] = request.Kind
            end
        end
    elseif request.Action == "ResolveTurn" then
        resolveTurn(state)
    end
    return snapshot(state)
end

Players.PlayerRemoving:Connect(function(player)
    states[player] = nil
    lastRequestAt[player] = nil
end)

print("[AnimeCombatServerV2] Server-authoritative speed combat, KO handling, effects, AI, and battle completion online.")

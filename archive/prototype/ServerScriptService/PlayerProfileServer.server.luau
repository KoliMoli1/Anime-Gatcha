local Players = game:GetService('Players')
local DataStoreService = game:GetService('DataStoreService')
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local core = ReplicatedStorage:WaitForChild('AnimeCombatCore')
local remotes = core:WaitForChild('Remotes')
local getCollection = remotes:WaitForChild('GetCollectionSnapshot')
local collectionUpdated = remotes:WaitForChild('CollectionUpdated')
local getProfile = remotes:WaitForChild('GetProfileSnapshot')
local profileUpdated = remotes:WaitForChild('ProfileUpdated')
local getTeamSelect = remotes:WaitForChild('GetTeamSelectSnapshot')
local setTeam = remotes:WaitForChild('SetSelectedTeam')
local definitions = require(core.Shared:WaitForChild('CharacterDefinitions'))
local profiles = require(script.Parent:WaitForChild('Services'):WaitForChild('ProfileRegistry'))

local PROFILE_STORE = DataStoreService:GetDataStore('AnimeGachaPlayerProfiles_v1')
local PROFILE_VERSION = 2
local DEFAULT_COINS = 1000
local MAX_RETRIES = RunService:IsStudio() and 1 or 3
local AUTOSAVE_SECONDS = 120

local GachaRules = require(core.Shared:WaitForChild('GachaRules'))
local BattleRewardRules = require(core.Shared:WaitForChild('BattleRewardRules'))
local grantBattleReward = script.Parent:WaitForChild('Services'):WaitForChild('GrantBattleReward')
local characterForRoll = GachaRules.CharacterForRoll

local loading = {}
local loadFailed = {}
local studioFallback = {}

local function defaultProfile()
    local obtainedAt = os.time()
    return {
        Version = PROFILE_VERSION,
        Coins = DEFAULT_COINS,
        -- All five training classes are free tutorial units for immediate team-building experiments.
        OwnedCharacters = {
            TrainingAttack = {Count = 1, FirstObtainedAt = obtainedAt},
            TrainingDefense = {Count = 1, FirstObtainedAt = obtainedAt},
            TrainingSupport = {Count = 1, FirstObtainedAt = obtainedAt},
            TrainingDisrupt = {Count = 1, FirstObtainedAt = obtainedAt},
            TrainingSpeed = {Count = 1, FirstObtainedAt = obtainedAt},
        },
        SelectedTeam = {'TrainingAttack', 'TrainingDefense', 'TrainingSupport'},
        RewardClaims = {},
    }
end

local function sanitize(raw)
    local p = defaultProfile()
    if type(raw) ~= 'table' then return p end
    if type(raw.Version) == 'number' then p.Version = raw.Version end
    if type(raw.Coins) == 'number' and raw.Coins >= 0 then p.Coins = math.floor(raw.Coins) end
    if type(raw.OwnedCharacters) == 'table' then
        for id, entry in pairs(raw.OwnedCharacters) do
            if definitions[id] and type(entry) == 'table' and type(entry.Count) == 'number' and entry.Count > 0 then
                p.OwnedCharacters[id] = {
                    Count = 1,
                    FirstObtainedAt = type(entry.FirstObtainedAt) == 'number' and entry.FirstObtainedAt or os.time(),
                }
            end
        end
    end
    if type(raw.SelectedTeam) == 'table' then
        for i = 1, 3 do
            local id = raw.SelectedTeam[i]
            if type(id) == 'string' and p.OwnedCharacters[id] then p.SelectedTeam[i] = id end
        end
    end
    if type(raw.RewardClaims) == 'table' then
        local copied = 0
        for claimId, claimedAt in pairs(raw.RewardClaims) do
            if copied >= BattleRewardRules.MaxStoredClaims then break end
            if BattleRewardRules.IsValidClaimId(claimId) and type(claimedAt) == 'number' then
                p.RewardClaims[claimId] = claimedAt
                copied += 1
            end
        end
    end
    p.Version = PROFILE_VERSION
    return p
end

local function ensureTutorialRoster(profile)
    local obtainedAt = os.time()
    for _, id in ipairs({'TrainingAttack', 'TrainingDefense', 'TrainingSupport', 'TrainingDisrupt', 'TrainingSpeed'}) do
        if definitions[id] and not profile.OwnedCharacters[id] then
            profile.OwnedCharacters[id] = {Count = 1, FirstObtainedAt = obtainedAt}
        end
    end
    return profile
end

local function retry(label, callback)
    local lastError
    for attempt = 1, MAX_RETRIES do
        local ok, result = pcall(callback)
        if ok then return true, result end
        lastError = result
        warn('[PlayerProfileServer] '..label..' attempt '..attempt..' failed: '..tostring(result))
        task.wait(attempt)
    end
    return false, lastError
end

local function collectionSnapshot(profile)
    local result = {}
    for id, entry in pairs(profile.OwnedCharacters) do
        local definition = definitions[id]
        if definition then
            local className = 'Unknown'
            for class in pairs(definition.Classes or {}) do className = class break end
            table.insert(result, {
                Id = id,
                DisplayName = definition.DisplayName,
                Rarity = definition.Rarity,
                Class = className,
                Count = entry.Count,
                FirstObtainedAt = entry.FirstObtainedAt,
            })
        end
    end
    table.sort(result, function(a, b)
        if a.Rarity == b.Rarity then return a.Id < b.Id end
        return a.Rarity > b.Rarity
    end)
    return result
end

local function profileSnapshot(player)
    local profile = profiles[player]
    if not profile then
        return {Loaded = false, LoadFailed = loadFailed[player] == true}
    end
    return {
        Loaded = true,
        LoadFailed = false,
        StorageFallback = studioFallback[player] == true,
        Version = profile.Version,
        Coins = profile.Coins,
        OwnedCharacters = collectionSnapshot(profile),
        SelectedTeam = table.clone(profile.SelectedTeam),
    }
end

local function publish(player)
    local profile = profiles[player]
    if not profile then return end
    local collection = collectionSnapshot(profile)
    collectionUpdated:FireClient(player, collection)
    profileUpdated:FireClient(player, profileSnapshot(player))
end

local function loadProfile(player)
    loading[player] = true
    local key = 'Player_'..player.UserId
    local ok, raw = retry('Load '..key, function()
        return PROFILE_STORE:GetAsync(key)
    end)
    loading[player] = nil
    if not ok then
        if RunService:IsStudio() then
            profiles[player] = defaultProfile()
            studioFallback[player] = true
            warn('[PlayerProfileServer] DataStore unavailable in Studio; using temporary in-memory profile for play-test only.')
        else
            loadFailed[player] = true
            warn('[PlayerProfileServer] Profile unavailable for '..player.Name..'; rolls and writes remain disabled.')
            return
        end
    else
        profiles[player] = ensureTutorialRoster(sanitize(raw))
        loadFailed[player] = nil
    end
    local leaderstats = Instance.new('Folder')
    leaderstats.Name = 'leaderstats'
    leaderstats.Parent = player
    local coins = Instance.new('IntValue')
    coins.Name = 'Coins'
    coins.Value = profiles[player].Coins
    coins.Parent = leaderstats
    print('[PlayerProfileServer] Loaded '..player.Name..' with '..#collectionSnapshot(profiles[player])..' owned character types.')
    publish(player)
end

local function saveProfile(player)
    local profile = profiles[player]
    if not profile or loadFailed[player] or studioFallback[player] then return false, 'profile not persisted in current session' end
    local stats = player:FindFirstChild('leaderstats')
    local coins = stats and stats:FindFirstChild('Coins')
    if coins then profile.Coins = math.max(0, math.floor(coins.Value)) end
    local key = 'Player_'..player.UserId
    local data = sanitize(ensureTutorialRoster(profile))
    local ok, err = retry('Save '..key, function()
        return PROFILE_STORE:UpdateAsync(key, function()
            return data
        end)
    end)
    if ok then
        print('[PlayerProfileServer] Saved '..player.Name)
        return true
    end
    warn('[PlayerProfileServer] Save failed for '..player.Name..': '..tostring(err))
    return false, err
end

-- Server-only API for the future gacha roll service.
local function addCharacter(player, characterId, suppressPublish)
    if loading[player] or loadFailed[player] or not profiles[player] then return false, false, 'profile unavailable' end
    if type(characterId) ~= 'string' or not definitions[characterId] then return false, false, 'invalid character id' end
    local owned = profiles[player].OwnedCharacters[characterId]
    local duplicate = owned ~= nil
    if not owned then
        profiles[player].OwnedCharacters[characterId] = {Count = 1, FirstObtainedAt = os.time()}
    end
    if not suppressPublish then publish(player) end
    return true, duplicate
end

local function awardBattle(player, outcome, claimId)
    local profile = profiles[player]
    local amount = BattleRewardRules.CoinsForOutcome(outcome)
    if not profile or loading[player] or loadFailed[player] then return false, 0, 'profile unavailable' end
    if not amount or not BattleRewardRules.IsValidClaimId(claimId) then return false, 0, 'invalid reward request' end
    profile.RewardClaims = profile.RewardClaims or {}
    if profile.RewardClaims[claimId] then return false, 0, 'already claimed' end
    local claimCount = 0
    for _ in pairs(profile.RewardClaims) do claimCount += 1 end
    if claimCount >= BattleRewardRules.MaxStoredClaims then
        local oldestId, oldestAt
        for id, at in pairs(profile.RewardClaims) do
            if not oldestAt or at < oldestAt then oldestId, oldestAt = id, at end
        end
        if oldestId then profile.RewardClaims[oldestId] = nil end
    end
    profile.RewardClaims[claimId] = os.time()
    profile.Coins = math.max(0, math.floor(profile.Coins + amount))
    local stats = player:FindFirstChild('leaderstats')
    local coins = stats and stats:FindFirstChild('Coins')
    if coins then coins.Value = profile.Coins end
    publish(player)
    return true, amount, nil
end

grantBattleReward.OnInvoke = awardBattle

getCollection.OnServerInvoke = function(player)
    if not profiles[player] then return {} end
    return collectionSnapshot(profiles[player])
end

getProfile.OnServerInvoke = function(player)
    return profileSnapshot(player)
end

getTeamSelect.OnServerInvoke = function(player)
    local profile = profiles[player]
    if not profile then return {Loaded = false, OwnedCharacters = {}, SelectedTeam = {}} end
    return {Loaded = true, OwnedCharacters = collectionSnapshot(profile), SelectedTeam = table.clone(profile.SelectedTeam)}
end

setTeam.OnServerInvoke = function(player, requestedTeam)
    local profile = profiles[player]
    if not profile or loading[player] or loadFailed[player] then return {success = false, message = 'Profile is still loading.'} end
    if type(requestedTeam) ~= 'table' then return {success = false, message = 'Invalid team.'} end
    local validated = {}
    local seen = {}
    for i = 1, 3 do
        local id = requestedTeam[i]
        if type(id) ~= 'string' or not definitions[id] then return {success = false, message = 'Invalid character in slot '..i} end
        if seen[id] then return {success = false, message = 'Duplicate characters are not allowed.'} end
        if not profile.OwnedCharacters[id] then return {success = false, message = 'You do not own '..id} end
        seen[id] = true
        validated[i] = id
    end
    profile.SelectedTeam = validated
    publish(player)
    return {success = true, SelectedTeam = table.clone(validated)}
end

local rollRemote = ReplicatedStorage:FindFirstChild('GenerateRandomNumber')
local rng = Random.new()
local ROLL_COST = GachaRules.RollCost
local DUPLICATE_REWARD = GachaRules.DuplicateReward
local ROLL_COOLDOWN = GachaRules.RollCooldown
local lastRollAt = {}
if rollRemote and rollRemote:IsA('RemoteFunction') then
    rollRemote.OnServerInvoke = function(player)
        local profile = profiles[player]
        local stats = player:FindFirstChild('leaderstats')
        local coins = stats and stats:FindFirstChild('Coins')
        if not profile or loading[player] or loadFailed[player] or not coins then
            return {success = false, message = 'Profile is still loading.'}
        end
        if coins.Value < ROLL_COST then
            return {success = false, message = 'Not enough coins!', coins = coins.Value, cost = ROLL_COST}
        end
        local now = os.clock()
        local retryAfter = ROLL_COOLDOWN - (now - (lastRollAt[player] or -math.huge))
        if retryAfter > 0 then
            return {success = false, message = 'Please wait before rolling again.', coins = coins.Value, cost = ROLL_COST, retryAfter = retryAfter}
        end
        lastRollAt[player] = now
        coins.Value -= ROLL_COST
        profile.Coins = coins.Value
        local value = rng:NextInteger(1, 1000)
        local characterId = characterForRoll(value)
        local added, duplicate, addError = addCharacter(player, characterId, true)
        if not added then
            coins.Value += ROLL_COST
            profile.Coins = coins.Value
            return {success = false, message = addError or 'Roll mapping failed.', coins = coins.Value, cost = ROLL_COST}
        end
        local duplicateReward = 0
        if duplicate then
            duplicateReward = DUPLICATE_REWARD
            coins.Value += duplicateReward
            profile.Coins = coins.Value
        end
        publish(player)
        return {
            success = true,
            value = value,
            characterId = characterId,
            coins = coins.Value,
            cost = ROLL_COST,
            collectionAdded = not duplicate,
            duplicate = duplicate,
            duplicateReward = duplicateReward,
        }
    end
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(loadProfile, player)
end)
Players.PlayerRemoving:Connect(function(player)
    saveProfile(player)
    profiles[player] = nil
    loading[player] = nil
    loadFailed[player] = nil
    studioFallback[player] = nil
    lastRollAt[player] = nil
end)

task.spawn(function()
    while task.wait(AUTOSAVE_SECONDS) do
        for player in pairs(profiles) do
            saveProfile(player)
        end
    end
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        saveProfile(player)
    end
end)

print('[PlayerProfileServer] Persistent profile/roster service online; roll ranges, safe duplicate compensation, and roll throttling are configured.')

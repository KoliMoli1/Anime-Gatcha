--!nonstrict
-- Player saves through ProfileStore (session locking, autosave, safe shutdown).
-- Owns the only writable copy of player data. Other services read with Get and
-- write through Update, which republishes the result to the client.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Shared = ReplicatedStorage.Shared
local Schema = require(Shared.Rules.ProfileSchema)
local Characters = require(Shared.Content.Characters)
local Items = require(Shared.Content.Items)

local STORE_NAME = "PlayerData_v3"
local LEGACY_STORE_NAME = "AnimeGachaPlayerProfiles_v1"

local ProfileService = {}

local store = ProfileStore.New(STORE_NAME, Schema.default(0, Characters))
local profiles: { [Player]: any } = {}
local shuttingDown = false
local loadedCallbacks: { (Player) -> () } = {}
local changedCallbacks: { (Player) -> () } = {}

local function migrateLegacy(player: Player, data)
	if data.MigratedFromV2 then
		return
	end
	local ok, raw = pcall(function()
		return DataStoreService:GetDataStore(LEGACY_STORE_NAME):GetAsync("Player_" .. player.UserId)
	end)
	if not ok then
		-- Leave the flag unset so the next session retries.
		warn(`[ProfileService] Legacy save unreadable for {player.Name}: {raw}`)
		return
	end
	if raw ~= nil then
		Schema.mergeV2(data, raw, os.time(), Characters)
		print(`[ProfileService] Migrated prototype save for {player.Name}`)
	end
	data.MigratedFromV2 = true
end

local function updateLeaderstats(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local gems = stats:FindFirstChild("Gems")
	if not gems then
		gems = Instance.new("IntValue")
		gems.Name = "Gems"
		gems.Parent = stats
	end
	gems.Value = Schema.totalGems(data)
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		player:Kick("Your save could not be loaded. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		-- Only a lost session lock means another server took the save.
		if not shuttingDown and player.Parent == Players then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	migrateLegacy(player, profile.Data)
	Schema.sanitize(profile.Data, os.time(), Characters, Items)
	profiles[player] = profile
	updateLeaderstats(player, profile.Data)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player)
	end
end

-- Read-only view. Do not mutate the result; use Update.
function ProfileService.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

function ProfileService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Runs mutate(data) and republishes if it returns true (or nil). Returns mutate's results.
function ProfileService.Update(player: Player, mutate: (any) -> ...any): ...any
	local profile = profiles[player]
	if not profile then
		return false, "Your profile is still loading."
	end
	local results = table.pack(mutate(profile.Data))
	if results[1] ~= false then
		updateLeaderstats(player, profile.Data)
		for _, callback in changedCallbacks do
			task.spawn(callback, player)
		end
	end
	return table.unpack(results, 1, results.n)
end

function ProfileService.OnLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player in profiles do
		task.spawn(callback, player)
	end
end

function ProfileService.OnChanged(callback: (Player) -> ())
	table.insert(changedCallbacks, callback)
end

-- Admin tool: replace a player's data with a fresh default.
function ProfileService.Reset(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local fresh = Schema.default(os.time(), Characters)
	fresh.MigratedFromV2 = true
	profile.Data = fresh
	updateLeaderstats(player, fresh)
	for _, callback in changedCallbacks do
		task.spawn(callback, player)
	end
	return true
end

function ProfileService.Start()
	game:BindToClose(function()
		shuttingDown = true
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			profile:EndSession()
		end
	end)
end

return ProfileService

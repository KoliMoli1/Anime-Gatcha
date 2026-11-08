--!nonstrict
-- The local player's profile as Vide sources, kept fresh from RosterService
-- (GetProfileSnapshot on start, then every ProfileUpdated push) and the hub zone attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local source = vide.source

local ProfileState = {
	-- RosterService.ProfileSnapshot: { Loaded, Gems, OwnedCharacters, OwnedItems, Team, ... }
	profile = source(nil :: any),
	-- Hub circle the player stands in ("Summon", "PvP", ...), or nil.
	zone = source(nil :: string?),
}

local started = false

function ProfileState.Start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local profileUpdated = remotes:WaitForChild("ProfileUpdated") :: RemoteEvent
	profileUpdated.OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" and snapshot.Loaded then
			ProfileState.profile(snapshot)
		end
	end)
	task.spawn(function()
		local remote = remotes:WaitForChild("GetProfileSnapshot") :: RemoteFunction
		for _ = 1, 10 do
			local ok, snapshot = pcall(remote.InvokeServer, remote)
			if ok and type(snapshot) == "table" and snapshot.Loaded then
				if not ProfileState.profile() then
					ProfileState.profile(snapshot)
				end
				return
			end
			task.wait(1)
		end
	end)
	local function syncZone()
		ProfileState.zone(player:GetAttribute("Zone"))
	end
	player:GetAttributeChangedSignal("Zone"):Connect(syncZone)
	syncZone()
end

-- Owned character entry by id (Dupes, Capacity, ...), or nil.
function ProfileState.owned(id: string)
	local profile = ProfileState.profile()
	if not profile then
		return nil
	end
	for _, entry in profile.OwnedCharacters do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

return ProfileState

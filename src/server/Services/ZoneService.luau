--!strict
-- Hub circles (roadmap Phase 4): tracks which mode circle each player stands in and
-- publishes it as the player's "Zone" attribute. Clients open that mode's panel from it.
-- The server is the authority, so queue joins can't be spoofed from the client:
-- stepping into PvP joins the queue, stepping out (or starting a battle) leaves it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HubZones = require(ReplicatedStorage.Shared.Content.HubZones)
local PvPQueueService = require(script.Parent.PvPQueueService)

local ZoneService = {}

ZoneService.TICK = 0.2

local current: { [Player]: string? } = {}

local function zoneFor(player: Player): string?
	if player:GetAttribute("InBattle") then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local zone = HubZones.at(root.Position)
	return zone and zone.Id
end

local function onExit(player: Player, zoneId: string)
	if zoneId == "PvP" then
		PvPQueueService.Leave(player)
	end
end

local function onEnter(player: Player, zoneId: string)
	if zoneId == "PvP" then
		PvPQueueService.Join(player)
	end
end

function ZoneService.Update(player: Player)
	local nextZone = zoneFor(player)
	local previous = current[player]
	if nextZone == previous then
		return
	end
	current[player] = nextZone
	player:SetAttribute("Zone", nextZone)
	if previous then
		onExit(player, previous)
	end
	if nextZone then
		onEnter(player, nextZone)
	end
end

function ZoneService.Start()
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(ZoneService.Update, player)
				if not ok then
					warn("[ZoneService]", err)
				end
			end
			task.wait(ZoneService.TICK)
		end
	end)
end

return ZoneService

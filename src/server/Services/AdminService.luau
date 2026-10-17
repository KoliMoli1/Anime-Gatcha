--!nonstrict
--!nolint DeprecatedApi
-- Cmdr admin console (press F2). Only the group owner/admins, or anyone in Studio,
-- may run commands. Only Help is registered from the defaults on purpose.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Cmdr = require(ServerScriptService.ServerPackages.Cmdr) :: any

local AdminService = {}

-- Roblox group roles: Owner = 255, Admin = 254 by default.
AdminService.MIN_GROUP_RANK = 254

function AdminService.IsAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroupAsync, player, game.CreatorId)
		return ok and rank >= AdminService.MIN_GROUP_RANK
	end
	return player.UserId == game.CreatorId
end

function AdminService.Start()
	Cmdr.Registry:RegisterDefaultCommands({ "Help" })
	Cmdr.Registry:RegisterCommandsIn(script.Parent.Parent.Cmdr.Commands)
	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		local executor = context.Executor
		if executor and not AdminService.IsAdmin(executor) then
			return "Admins only."
		end
		return nil
	end)
	-- Lets the client show admin-only tools (debug panel). Commands are still checked on the server.
	local function mark(player: Player)
		player:SetAttribute("IsAdmin", AdminService.IsAdmin(player))
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		task.spawn(mark, player)
	end
end

return AdminService

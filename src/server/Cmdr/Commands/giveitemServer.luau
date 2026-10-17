local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Content.Items)
local ProfileService = require(game:GetService("ServerScriptService").Server.Services.ProfileService)

return function(_context, player: Player, itemId: string)
	if itemId ~= "all" and not Items[itemId] then
		return `Unknown item {itemId}.`
	end
	local ok = ProfileService.Update(player, function(data)
		for id in Items do
			if itemId == "all" or id == itemId then
				data.Items[id] = data.Items[id] or { ObtainedAt = os.time() }
			end
		end
		return true
	end)
	return if ok then `Gave {itemId} to {player.Name}.` else "That profile is not loaded."
end

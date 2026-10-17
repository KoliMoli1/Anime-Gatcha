local ProfileService = require(game:GetService("ServerScriptService").Server.Services.ProfileService)

return function(_context, player: Player)
	return if ProfileService.Reset(player) then `Reset {player.Name}'s profile.` else "That profile is not loaded."
end

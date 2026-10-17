local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Characters = require(ReplicatedStorage.Shared.Content.Characters)
local Schema = require(ReplicatedStorage.Shared.Rules.ProfileSchema)
local ProfileService = require(game:GetService("ServerScriptService").Server.Services.ProfileService)

return function(_context, player: Player, characterId: string)
	local def = Characters[characterId]
	if not def then
		return `Unknown character {characterId}.`
	end
	local ok, outcome = ProfileService.Update(player, function(data)
		return true, (Schema.grantCharacter(data, def, os.time()))
	end)
	return if ok then `{player.Name}: {def.Name} ({outcome}).` else "That profile is not loaded."
end

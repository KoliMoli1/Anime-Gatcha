local EconomyService = require(game:GetService("ServerScriptService").Server.Services.EconomyService)

return function(context, player: Player, amount: number)
	if amount <= 0 or amount > 1_000_000 then
		return "Amount must be between 1 and 1,000,000."
	end
	local ok = EconomyService.GrantGems(player, amount, `admin {context.Executor.Name}`)
	return if ok then `Gave {amount} gems to {player.Name}.` else "That profile is not loaded."
end

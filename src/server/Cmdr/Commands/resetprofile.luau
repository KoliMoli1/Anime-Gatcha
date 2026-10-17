return {
	Name = "resetprofile",
	Description = "Wipe a player's save back to a fresh profile (testing).",
	Group = "GameAdmin",
	Args = {
		{ Type = "player", Name = "Player", Description = "Whose save to reset." },
	},
}

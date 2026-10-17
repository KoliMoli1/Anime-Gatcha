return {
	Name = "givegems",
	Description = "Give earned gems to a player (testing).",
	Group = "GameAdmin",
	Args = {
		{ Type = "player", Name = "Player", Description = "Who receives the gems." },
		{ Type = "integer", Name = "Amount", Description = "How many gems." },
	},
}

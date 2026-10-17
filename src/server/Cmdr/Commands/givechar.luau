return {
	Name = "givechar",
	Description = "Grant a character (or a duplicate) to a player (testing).",
	Group = "GameAdmin",
	Args = {
		{ Type = "player", Name = "Player", Description = "Who receives the character." },
		{ Type = "string", Name = "CharacterId", Description = "Character id, e.g. TrainingSpeed." },
	},
}

return {
	Name = "giveitem",
	Description = "Grant an item to a player (testing). Use 'all' for every item.",
	Group = "GameAdmin",
	Args = {
		{ Type = "player", Name = "Player", Description = "Who receives the item." },
		{ Type = "string", Name = "ItemId", Description = "Item id, e.g. storm_crown, or all." },
	},
}

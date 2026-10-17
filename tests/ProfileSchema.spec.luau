local Schema = require("../src/shared/Rules/ProfileSchema")
local Characters = require("../src/shared/Content/Characters")
local Items = require("../src/shared/Content/Items")

local NOW = 1_800_000_000

return function(t)
	t.test("default profile owns the starters and a valid team", function()
		local data = Schema.default(NOW, Characters)
		for id, def in Characters do
			if def.Starter then
				t.truthy(data.Characters[id], id)
			end
		end
		t.equal(#data.Team, 3)
		t.equal(Schema.totalGems(data), Schema.STARTING_GEMS)
	end)

	t.test("v2 prototype saves migrate coins, roster, team and claims", function()
		local data = Schema.default(NOW, Characters)
		Schema.mergeV2(data, {
			Coins = 345,
			OwnedCharacters = { TrainingSpeed = { Count = 1, FirstObtainedAt = 123 }, NotACharacter = { Count = 1 } },
			SelectedTeam = { "TrainingSpeed", "TrainingDisrupt", "TrainingAttack" },
			RewardClaims = { ["PvE_1_2_3"] = 99, bad = 1 },
		}, NOW, Characters)
		Schema.sanitize(data, NOW, Characters, Items)
		t.equal(data.Gems.Earned, 345)
		t.equal(data.Characters.TrainingSpeed.ObtainedAt, 123)
		t.equal(data.Characters.NotACharacter, nil)
		t.equal(data.Team[1].Id, "TrainingSpeed")
		t.equal(data.RewardClaims["PvE_1_2_3"], 99)
		t.equal(data.RewardClaims.bad, nil)
	end)

	t.test("sanitize repairs bad data", function()
		local data = Schema.default(NOW, Characters)
		data.Gems.Earned = -50
		data.Characters.TrainingAttack = nil
		data.Items.not_real = { ObtainedAt = 1 }
		data.Team = { { Id = "TrainingAttack", Items = { "not_real" } }, { Id = "x", Items = {} } }
		Schema.sanitize(data, NOW, Characters, Items)
		t.equal(data.Gems.Earned, 0)
		t.truthy(data.Characters.TrainingAttack, "starter restored")
		t.equal(data.Items.not_real, nil)
		t.equal(#data.Team, 3, "team repaired")
	end)

	t.test("duplicates raise capacity, then overflow to coins", function()
		local data = Schema.default(NOW, Characters)
		local def = Characters.TrainingAttack
		for i = 1, 5 do
			local kind = Schema.grantCharacter(data, def, NOW)
			t.equal(kind, "Duplicate", "dupe " .. i)
		end
		local kind, coins = Schema.grantCharacter(data, def, NOW)
		t.equal(kind, "Overflow")
		t.equal(coins, 25)
		t.equal(data.CosmeticCoins, 25)
	end)

	t.test("earned gems are spent before paid gems", function()
		local data = Schema.default(NOW, Characters)
		data.Gems = { Paid = 50, Earned = 30 }
		t.truthy(Schema.spendGems(data, 40))
		t.equal(data.Gems.Earned, 0)
		t.equal(data.Gems.Paid, 40)
		t.falsy(Schema.spendGems(data, 41))
	end)
end

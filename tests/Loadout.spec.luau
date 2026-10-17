local Loadout = require("../src/shared/Rules/Loadout")
local Characters = require("../src/shared/Content/Characters")
local Items = require("../src/shared/Content/Items")

local owned = {
	TrainingAttack = { Dupes = 0 },
	TrainingDefense = { Dupes = 5 },
	TrainingSupport = { Dupes = 0 },
}
local ownedItems = { storm_crown = true, duelist_edge = true, swift_boots = true, worn_band = true }

local function check(team)
	return Loadout.validateTeam(team, owned, ownedItems, Characters, Items)
end

return function(t)
	t.test("capacity grows with duplicates and caps at 5", function()
		t.equal(Loadout.capacity(5, 0), 12)
		t.equal(Loadout.capacity(5, 5), 32)
		t.equal(Loadout.capacity(5, 9), 32)
		t.equal(Loadout.capacity(4, 5), 25)
	end)

	t.test("valid team passes", function()
		local ok, err = check({
			{ Id = "TrainingAttack", Items = { "storm_crown" } },
			{ Id = "TrainingDefense", Items = { "duelist_edge", "swift_boots" } },
			{ Id = "TrainingSupport", Items = { "worn_band" } },
		})
		t.truthy(ok, err)
	end)

	t.test("an item can only be used once per team", function()
		local ok = check({
			{ Id = "TrainingAttack", Items = { "storm_crown" } },
			{ Id = "TrainingDefense", Items = { "storm_crown" } },
			{ Id = "TrainingSupport", Items = {} },
		})
		t.falsy(ok)
	end)

	t.test("items must fit capacity", function()
		-- 5-star with no dupes has 12 capacity; 10 + 8 = 18 does not fit.
		local ok = check({
			{ Id = "TrainingAttack", Items = { "storm_crown", "duelist_edge" } },
			{ Id = "TrainingDefense", Items = {} },
			{ Id = "TrainingSupport", Items = {} },
		})
		t.falsy(ok)
	end)

	t.test("duplicate and unowned characters are rejected", function()
		t.falsy(check({
			{ Id = "TrainingAttack", Items = {} },
			{ Id = "TrainingAttack", Items = {} },
			{ Id = "TrainingSupport", Items = {} },
		}))
		t.falsy(check({
			{ Id = "TrainingAttack", Items = {} },
			{ Id = "TrainingSpeed", Items = {} },
			{ Id = "TrainingSupport", Items = {} },
		}))
	end)
end

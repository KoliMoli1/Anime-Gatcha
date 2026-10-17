local BattleText = require("../src/shared/Combat/BattleText")
local BattleSession = require("../src/shared/Combat/BattleSession")
local BattleAI = require("../src/shared/Combat/BattleAI")
local Rng = require("../src/shared/Util/Rng")
local Characters = require("../src/shared/Content/Characters")

local names = { { "Ace", "Bulwark", "Cleric" }, { "Dash", "Echo", "Fort" } }

return function(t)
	t.test("own and enemy units are labelled from the viewer's side", function()
		t.equal(BattleText.unit(names, 1, 1, 2), "Your Bulwark")
		t.equal(BattleText.unit(names, 1, 2, 3), "Enemy Fort")
		t.equal(BattleText.unit(names, 2, 2, 3), "Your Fort")
	end)

	t.test("stat changes format percent vs points", function()
		t.equal(BattleText.statChange("ATK", -0.24), "ATK -24%")
		t.equal(BattleText.statChange("CritRate", 0.25), "Crit +25")
	end)

	t.test("every event from a real battle can be described without errors", function()
		local function team(a, b, c)
			return {
				{ Character = Characters[a], Items = {} },
				{ Character = Characters[b], Items = {} },
				{ Character = Characters[c], Items = {} },
			}
		end
		for seed = 1, 10 do
			local session = BattleSession.new({
				Seed = seed,
				Teams = {
					team("TrainingAttack", "TrainingDefense", "TrainingSupport"),
					team("TrainingSpeed", "TrainingDisrupt", "TrainingDefense"),
				},
			})
			local rng = Rng.new(seed)
			local events = session:TakeEvents()
			while session.Phase ~= "Finished" do
				assert(session:Submit(1, BattleAI.choose(session, 1, rng, { Randomness = 0.3 })))
				assert(session:Submit(2, BattleAI.choose(session, 2, rng, { Randomness = 0.3 })))
				for _, event in session:Resolve() do
					table.insert(events, event)
				end
			end
			local described = 0
			for _, event in events do
				local line = BattleText.describe(event, names, 1)
				if line then
					described += 1
				end
			end
			t.truthy(described > 0, "some lines")
		end
	end)
end

local Rng = require("../src/shared/Util/Rng")
local Stats = require("../src/shared/Combat/Stats")
local BattleSession = require("../src/shared/Combat/BattleSession")
local BattleAI = require("../src/shared/Combat/BattleAI")
local Characters = require("../src/shared/Content/Characters")
local Items = require("../src/shared/Content/Items")

local function unit(id, items)
	return { Character = Characters[id], Items = items or {} }
end

local function team(a, b, c)
	return { unit(a), unit(b), unit(c) }
end

local function newBattle(seed, teamA, teamB)
	return BattleSession.new({ Seed = seed, Teams = { teamA, teamB } })
end

local function basicAll()
	return { { Skill = 1, Target = 1 }, { Skill = 1, Target = 1 }, { Skill = 1, Target = 1 } }
end

return function(t)
	t.test("rng is deterministic per seed", function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 20 do
			t.equal(a:next(), b:next())
		end
		local r = Rng.new(7)
		for _ = 1, 500 do
			local v = r:integer(3, 5)
			t.truthy(v >= 3 and v <= 5, "integer in range")
		end
	end)

	t.test("damage uses multiplicative defense with a floor", function()
		t.equal(Stats.damage(100, 1, 100, 1), 50)
		t.equal(Stats.damage(100, 1, 0, 1), Stats.damage(100, 1, 20, 1), "DEF floor 20")
		t.equal(Stats.damage(100, 2, 0, 1.5), 250)
	end)

	t.test("stat modifiers are capped and floored", function()
		t.equal(Stats.apply("ATK", 100, 0.9), 150, "cap +50%")
		t.equal(Stats.apply("ATK", 100, -0.9), 50, "cap -50%")
		t.equal(Stats.apply("DEF", 25, -0.5), 20, "DEF floor")
		t.equal(Stats.apply("CritRate", 0.3, -0.5), 0.15, "minimum 50% of base")
	end)

	t.test("effectiveness and resistance scale debuffs", function()
		t.near(Stats.debuffPower(-0.20, 0.30, 0.10), -0.24, 1e-9, "power up")
		t.near(Stats.debuffPower(-0.20, 0.30, 0.50), -0.16, 1e-9, "power down")
		t.near(Stats.debuffPower(-0.20, 2, 0), -0.30, 1e-9, "power cap 1.5x")
		t.equal(Stats.debuffTurns(2, 0.40, 0.05), 3, "duration +1")
		t.equal(Stats.debuffTurns(2, 0.0, 0.40), 1, "duration -1")
		t.equal(Stats.debuffTurns(1, 0.0, 0.40), 1, "duration minimum 1")
	end)

	t.test("items raise pre-battle stats", function()
		local character = Characters.TrainingAttack
		local boosted = Stats.withItems(character, { Items.storm_crown, Items.swift_boots })
		t.equal(boosted.ATK, math.floor(character.Stats.ATK * 1.10 + 0.5))
		t.near(boosted.CritRate, character.Stats.CritRate + 0.05, 1e-9)
		t.equal(boosted.SpeedMax, math.floor(character.Speed.Max * 1.12 + 0.5))
	end)

	t.test("same seed and actions replay identically", function()
		local function play(seed)
			local s = newBattle(
				seed,
				team("TrainingAttack", "TrainingDefense", "TrainingSupport"),
				team("TrainingSpeed", "TrainingDisrupt", "TrainingDefense")
			)
			local rngA, rngB = Rng.new(seed + 1), Rng.new(seed + 2)
			local log = {}
			while s.Phase ~= "Finished" do
				assert(s:Submit(1, BattleAI.choose(s, 1, rngA)))
				assert(s:Submit(2, BattleAI.choose(s, 2, rngB)))
				for _, e in s:Resolve() do
					if e.Type == "Damage" then
						table.insert(log, e.Amount)
					end
				end
			end
			return table.concat(log, ","), s.Winner
		end
		local a, wa = play(99)
		local b, wb = play(99)
		t.equal(a, b, "damage log")
		t.equal(wa, wb, "winner")
	end)

	t.test("energy limits submitted skills", function()
		local s = newBattle(
			1,
			team("TrainingAttack", "TrainingDefense", "TrainingSupport"),
			team("TrainingSpeed", "TrainingDisrupt", "TrainingDefense")
		)
		local regen = Characters.TrainingAttack.EnergyRegen
			+ Characters.TrainingDefense.EnergyRegen
			+ Characters.TrainingSupport.EnergyRegen
		t.equal(s.Teams[1].Energy, BattleSession.START_ENERGY + regen, "start energy plus round-1 regen")
		s.Teams[1].Energy = 5
		-- Attack ultimate (5) + Defense skill (2) = 7 > 5.
		t.falsy(s:Submit(1, { { Skill = 3, Target = 1 }, { Skill = 2 }, { Skill = 1, Target = 1 } }), "over budget")
		-- Attack skill (3) + Defense skill (2) + Support basic (0) = 5.
		t.truthy(s:Submit(1, { { Skill = 2, Target = 1 }, { Skill = 2 }, { Skill = 1, Target = 1 } }), "exactly fits")
	end)

	t.test("taunt redirects single-target attacks", function()
		local s = newBattle(
			5,
			team("TrainingAttack", "TrainingSupport", "TrainingDisrupt"),
			team("TrainingSpeed", "TrainingDefense", "TrainingSupport")
		)
		s.Teams[2].Energy = 10
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1, Target = 1 }, { Skill = 1, Target = 1 } }))
		assert(s:Submit(2, { { Skill = 1, Target = 1 }, { Skill = 2 }, { Skill = 1, Target = 1 } }))
		local hitsOnTank, hitsElsewhere = 0, 0
		for _, e in s:Resolve() do
			if e.Type == "Damage" and e.Side == 2 and not e.Counter then
				if e.Slot == 2 then
					hitsOnTank += 1
				else
					hitsElsewhere += 1
				end
			end
		end
		t.equal(hitsElsewhere, 0, "taunt acts at speed 80, before every attacker")
		t.truthy(hitsOnTank >= 1, "attacks land on the taunter")
	end)

	t.test("shield absorbs damage before HP", function()
		local s = newBattle(
			11,
			team("TrainingAttack", "TrainingSupport", "TrainingDisrupt"),
			team("TrainingDefense", "TrainingSupport", "TrainingSpeed")
		)
		s.Teams[2].Energy = 10
		assert(s:Submit(1, basicAll()))
		assert(s:Submit(2, { { Skill = 3 }, { Skill = 1, Target = 1 }, { Skill = 1, Target = 1 } }))
		local absorbed = 0
		for _, e in s:Resolve() do
			if e.Type == "Damage" and e.Side == 2 then
				absorbed += e.Absorbed
			end
		end
		t.truthy(absorbed > 0, "Bulwark shield soaked damage")
	end)

	t.test("battles always end", function()
		for seed = 1, 40 do
			local s = newBattle(
				seed,
				team("TrainingDefense", "TrainingSupport", "TrainingDisrupt"),
				team("TrainingDefense", "TrainingSupport", "TrainingDisrupt")
			)
			local rng = Rng.new(seed)
			while s.Phase ~= "Finished" do
				assert(s:Submit(1, BattleAI.choose(s, 1, rng, { Randomness = 0.3 })))
				assert(s:Submit(2, BattleAI.choose(s, 2, rng, { Randomness = 0.3 })))
				s:Resolve()
			end
			t.truthy(s.Round <= s.MaxRounds, "round cap")
		end
	end)

	t.test("snapshot hides enemy speed rolls", function()
		local s = newBattle(
			3,
			team("TrainingAttack", "TrainingDefense", "TrainingSupport"),
			team("TrainingSpeed", "TrainingDisrupt", "TrainingDefense")
		)
		local view = s:Snapshot(1)
		t.truthy(view.Teams[1].Units[1].Speed ~= nil, "own speed visible")
		t.equal(view.Teams[2].Units[1].Speed, nil, "enemy speed hidden")
	end)
end

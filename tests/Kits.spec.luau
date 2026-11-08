-- Launch 5-star kits (roadmap "Character kits" tab): each signature gimmick in a controlled
-- 3v3 against idle units, plus AI soak battles with every kit on the field.
local BattleSession = require("../src/shared/Combat/BattleSession")
local BattleAI = require("../src/shared/Combat/BattleAI")
local Classes = require("../src/shared/Content/Classes")
local Characters = require("../src/shared/Content/Characters")
local SkillContent = require("../src/shared/Content/Skills")
local Rng = require("../src/shared/Util/Rng")

local skills = table.clone(SkillContent.Skills)
local passives = table.clone(SkillContent.Passives)
skills.t_wait = { Id = "t_wait", Name = "Wait", Kind = "Basic", Cost = 0, Target = "Self", Description = "" }
skills.t_stun = {
	Id = "t_stun",
	Name = "Stun",
	Kind = "Skill",
	Cost = 0,
	Target = "Enemy",
	PrioritySpeed = 999,
	Effects = { { Kind = "Stun", To = "Target", Chance = 1, Turns = 1 } },
	Description = "",
}

local function def(id, class, skillIds, stats)
	local base = Classes.statsFor(class, 5)
	for key, value in stats or {} do
		base[key] = value
	end
	return {
		Id = id,
		Name = id,
		Rarity = 5,
		Class = class,
		Stats = base,
		Speed = { Min = 50, Max = 50 },
		EnergyRegen = 1,
		Skills = skillIds,
	}
end

local idle = def("Idle", "Defense", { "t_wait", "t_wait", "t_wait" }, { HP = 5000 })

local function unit(d)
	return { Character = d, Items = {} }
end

local function battle(a, b, seed)
	local teams = {}
	for side, list in { a, b } do
		teams[side] = {}
		for slot, d in list do
			teams[side][slot] = unit(d)
		end
	end
	return BattleSession.new({ Seed = seed or 5, Teams = teams, Skills = skills, Passives = passives })
end

local function waitAll()
	return { { Skill = 1 }, { Skill = 1 }, { Skill = 1 } }
end

local function kill(s, side, slot)
	local u = s.Teams[side].Units[slot]
	u.HP = 0
	u.Alive = false
end

local function find(events, kind, side, slot)
	for _, e in events do
		if e.Type == kind and (side == nil or e.Side == side) and (slot == nil or e.Slot == slot) then
			return e
		end
	end
	return nil
end

local function round(s, actionsA, actionsB)
	s.Teams[1].Energy = 10
	assert(s:Submit(1, actionsA))
	assert(s:Submit(2, actionsB or waitAll()))
	return s:Resolve()
end

local function barrierOf(u)
	for _, effect in u.Effects do
		if effect.Key == "kojo_barrier" then
			return effect.Amount
		end
	end
	return 0
end

return function(t)
	t.test("Boku: each first use fills the Power Meter, a full meter transforms him", function()
		local s = battle({ Characters.Boku, idle, idle }, { idle, idle, idle })
		kill(s, 1, 2)
		kill(s, 1, 3)
		local boku = s.Teams[1].Units[1]
		round(s, { [1] = { Skill = 1, Target = 1 } })
		t.equal(boku.Kit.Meter, 1)
		t.near(boku.Perm.ATK, 0.05, 1e-9, "+5% ATK per segment")
		round(s, { [1] = { Skill = 1, Target = 1 } })
		t.equal(boku.Kit.Meter, 1, "repeat use does not fill again")
		round(s, { [1] = { Skill = 2, Target = 1 } })
		local events = round(s, { [1] = { Skill = 3, Target = 1 } })
		t.truthy(find(events, "Transform", 1, 1), "transformed (fallen allies count as done)")
		t.equal(boku.Kit.Meter, 3)
		t.equal(boku.Skills[1].Id, "boku_t1")
		t.falsy(s:Submit(1, { [1] = { Skill = 3, Target = 1 } }), "Charging blocks the finisher next round")
	end)

	t.test("Kojo: barrier taunts, decays per hit and per round", function()
		local s = battle({ Characters.Kojo, idle, idle }, { Characters.TrainingAttack, idle, idle })
		local kojo = s.Teams[1].Units[1]
		t.near(barrierOf(kojo), 0.75, 1e-9, "starts at 75%")
		local events = round(
			s,
			{ { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } },
			{ { Skill = 1, Target = 3 }, { Skill = 1 }, { Skill = 1 } }
		)
		local hit = find(events, "Damage", 1, nil)
		t.truthy(hit, "the enemy attacked")
		t.equal(hit.Slot, 1, "taunt redirected the hit onto Kojo")
		t.near(barrierOf(kojo), 0.75 - 0.05 - 0.25, 1e-9, "one hit and one round end")
		-- Round 2: the enemy Attack unit's basic lands on him again.
		round(s, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } })
		t.near(barrierOf(kojo), 0.45 - 0.05 - 0.25, 1e-9)
		t.falsy(kojo.Kit.UniqueUsed)
	end)

	t.test("Sasta: a failed Devil Seal costs a third of his HP and locks the seal a round", function()
		local s = battle({ Characters.Sasta, idle, idle }, { idle, idle, idle })
		local sasta = s.Teams[1].Units[1]
		local start = sasta.HP
		round(s, { { Skill = 3 }, { Skill = 1 }, { Skill = 1 } })
		round(s, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } })
		t.equal(sasta.HP, start - math.floor(start / 3 + 0.5))
		t.falsy(sasta.Kit.Transformed)
		s.Teams[1].Energy = 10
		t.falsy(s:Submit(1, { { Skill = 3 }, { Skill = 1 }, { Skill = 1 } }), "seal on cooldown")
	end)

	t.test("Sasta: dropping to 35% inside the seal window turns him into the devil", function()
		local hitter = def("Hitter", "Attack", { "atk_basic", "t_wait", "t_wait" }, { ATK = 2000 })
		local s = battle({ Characters.Sasta, idle, idle }, { hitter, idle, idle })
		local sasta = s.Teams[1].Units[1]
		-- The hitter (speed 50) waits in round 1 so Sasta (speed 20-30) gets the seal up first.
		round(s, { { Skill = 3 }, { Skill = 1 }, { Skill = 1 } }, { { Skill = 2 }, { Skill = 1 }, { Skill = 1 } })
		local events = round(
			s,
			{ { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } },
			{ { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }
		)
		t.truthy(find(events, "Transform", 1, 1), "transformed instead of dying")
		t.truthy(sasta.Alive)
		t.equal(sasta.Class, "Attack")
		t.equal(sasta.Skills[1].Id, "sasta_d1")
		t.truthy(sasta.ReviveUsed, "counts as his one revive")
		t.equal(sasta.HP, math.floor(sasta.MaxHP * 0.8 + 0.5), "comes back at 80% of max HP")
	end)

	t.test("Shade: immune to debuffs for rounds 1-3", function()
		local stunner = def("Stunner", "Disrupt", { "t_stun", "t_wait", "t_wait" }, { EFF = 1 })
		local s = battle({ Characters.Shade, idle, idle }, { stunner, idle, idle })
		local events = round(
			s,
			{ { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } },
			{ { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }
		)
		t.falsy(find(events, "Stunned", 1, 1), "not stunned in round 1")
	end)

	t.test("Shade: raises a fallen ally as a shadow once per battle", function()
		local s = battle({ Characters.Shade, idle, idle }, { idle, idle, idle })
		kill(s, 1, 2)
		local events = round(s, { [1] = { Skill = 3 }, [3] = { Skill = 1 } })
		local shadow = s.Teams[1].Units[2]
		t.truthy(find(events, "Shadow", 1, 2), "shadow event")
		t.truthy(shadow.Alive and shadow.IsShadow)
		t.equal(shadow.HP, 200)
		t.truthy(shadow.ReviveUsed, "a shadow can't revive again")
		kill(s, 1, 3)
		s.Teams[1].Energy = 10
		t.falsy(s:Submit(1, { [1] = { Skill = 3 }, [2] = { Skill = 1, Target = 1 } }), "once per battle")
	end)

	t.test("AI battles with every kit always finish and replay identically", function()
		local rosters = {
			{ "Boku", "Kojo", "Shade" },
			{ "Sasta", "TrainingSupport", "TrainingDisrupt" },
			{ "Shade", "Sasta", "TrainingSupport" },
			{ "Kojo", "Boku", "TrainingSpeed" },
		}
		local function play(seed, a, b)
			local function team(ids)
				local list = {}
				for i, id in ids do
					list[i] = unit(Characters[id])
				end
				return list
			end
			local s = BattleSession.new({ Seed = seed, Teams = { team(a), team(b) } })
			local rng = Rng.new(seed * 31)
			local log = {}
			while s.Phase ~= "Finished" do
				assert(s:Submit(1, BattleAI.choose(s, 1, rng, { Randomness = 0.2 })))
				assert(s:Submit(2, BattleAI.choose(s, 2, rng, { Randomness = 0.2 })))
				for _, e in s:Resolve() do
					table.insert(log, e.Type)
				end
			end
			t.truthy(s.Round <= s.MaxRounds, "round cap")
			return table.concat(log, ","), s.Winner
		end
		for seed = 1, 12 do
			for i, a in rosters do
				local b = rosters[(i % #rosters) + 1]
				local first, winner = play(seed, a, b)
				local again, winnerAgain = play(seed, a, b)
				t.equal(first, again, "same seed, same events")
				t.equal(winner, winnerAgain)
			end
		end
	end)
end

-- Burn, stun, energy steal, revive and follow-up hits.
local BattleSession = require("../src/shared/Combat/BattleSession")
local Classes = require("../src/shared/Content/Classes")
local SkillContent = require("../src/shared/Content/Skills")

local skills = table.clone(SkillContent.Skills)
local passives = table.clone(SkillContent.Passives)

local function addSkill(def)
	skills[def.Id] = def
	return def.Id
end

addSkill({ Id = "t_wait", Name = "Wait", Kind = "Basic", Cost = 0, Target = "Self", Description = "" })
addSkill({
	Id = "t_burn",
	Name = "Ignite",
	Kind = "Skill",
	Cost = 0,
	Target = "Enemy",
	Effects = { { Kind = "Burn", To = "Target", Amount = 0.06, Turns = 2 } },
	Description = "",
})
addSkill({
	Id = "t_big_burn",
	Name = "Inferno",
	Kind = "Skill",
	Cost = 0,
	Target = "Enemy",
	Effects = { { Kind = "Burn", To = "Target", Amount = 0.5, Turns = 2 } },
	Description = "",
})
addSkill({
	Id = "t_stun",
	Name = "Stun",
	Kind = "Skill",
	Cost = 0,
	Target = "Enemy",
	PrioritySpeed = 999,
	Effects = { { Kind = "Stun", To = "Target", Chance = 1, Turns = 1 } },
	Description = "",
})
addSkill({
	Id = "t_steal",
	Name = "Siphon",
	Kind = "Skill",
	Cost = 0,
	Target = "Enemy",
	Effects = { { Kind = "EnergySteal", To = "Target", Amount = 2 } },
	Description = "",
})
addSkill({
	Id = "t_revive",
	Name = "Rise",
	Kind = "Ultimate",
	Cost = 0,
	Target = "Self",
	Effects = { { Kind = "Revive", To = "FallenAlly", Amount = 0.4 } },
	Description = "",
})
addSkill({
	Id = "t_finisher",
	Name = "Finisher",
	Kind = "Skill",
	Cost = 0,
	Target = "Enemy",
	Multiplier = 0.1,
	FollowUp = { Threshold = 0.5, Multiplier = 0.1 },
	Description = "",
})
passives.t_phoenix = { Id = "t_phoenix", Name = "Phoenix", Description = "", Revive = { Health = 0.25 } }

local function def(id, class, skillIds, passive, stats)
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
		Passive = passive,
	}
end

local function unit(d)
	return { Character = d, Items = {} }
end

local idle = def("Idle", "Defense", { "t_wait", "t_wait", "t_wait" })

local function battle(teamA, teamB)
	return BattleSession.new({ Seed = 3, Teams = { teamA, teamB }, Skills = skills, Passives = passives })
end

local function waitAll()
	return { { Skill = 1 }, { Skill = 1 }, { Skill = 1 } }
end

local function eventsOf(events, kind)
	local found = {}
	for _, e in events do
		if e.Type == kind then
			table.insert(found, e)
		end
	end
	return found
end

return function(t)
	t.test("burn deals % of max HP at round end, ignoring DEF", function()
		local caster = def("Caster", "Disrupt", { "t_burn", "t_wait", "t_wait" }, nil, { EFF = 0 })
		local tank = def("Tank", "Defense", { "t_wait", "t_wait", "t_wait" }, nil, { RES = 0, DEF = 500 })
		local s = battle({ unit(caster), unit(idle), unit(idle) }, { unit(tank), unit(idle), unit(idle) })
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, waitAll()))
		local burns = eventsOf(s:Resolve(), "Burn")
		t.equal(#burns, 1)
		t.equal(burns[1].Amount, math.floor(s.Teams[2].Units[1].MaxHP * 0.06 + 0.5), "6% of max HP")
	end)

	t.test("burn strength is capped", function()
		local caster = def("Caster", "Disrupt", { "t_big_burn", "t_wait", "t_wait" })
		local s = battle({ unit(caster), unit(idle), unit(idle) }, { unit(idle), unit(idle), unit(idle) })
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, waitAll()))
		local burns = eventsOf(s:Resolve(), "Burn")
		t.equal(burns[1].Amount, math.floor(s.Teams[2].Units[1].MaxHP * BattleSession.BURN_CAP + 0.5))
	end)

	t.test("stunned unit skips its next action, then cannot be stunned again right away", function()
		local stunner = def("Stunner", "Disrupt", { "t_stun", "t_wait", "t_wait" }, nil, { EFF = 1 })
		local victim = def("Victim", "Attack", { "atk_basic", "t_wait", "t_wait" }, nil, { RES = 0 })
		local s = battle({ unit(stunner), unit(idle), unit(idle) }, { unit(victim), unit(idle), unit(idle) })
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		local events = s:Resolve()
		t.equal(#eventsOf(events, "Stunned"), 1, "skipped this round")
		t.equal(#eventsOf(events, "Damage"), 0, "victim never attacked")
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		events = s:Resolve()
		local missed = eventsOf(events, "EffectMissed")
		t.equal(#missed, 1, "immune for a round")
		t.equal(missed[1].Reason, "Immune")
		t.truthy(#eventsOf(events, "Damage") >= 1, "victim acts again")
	end)

	t.test("energy steal moves energy between teams", function()
		local thief = def("Thief", "Speed", { "t_steal", "t_wait", "t_wait" })
		local s = battle({ unit(thief), unit(idle), unit(idle) }, { unit(idle), unit(idle), unit(idle) })
		s.Teams[1].Energy = 2
		s.Teams[2].Energy = 5
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, waitAll()))
		local stolen = eventsOf(s:Resolve(), "Effect")[1]
		t.equal(stolen.Kind, "EnergySteal")
		t.equal(stolen.Amount, 2)
		-- The next round's regen (+3 per team here) lands on top.
		t.equal(s.Teams[1].Energy, 2 + 2 + 3, "thief gained 2")
		t.equal(s.Teams[2].Energy, 5 - 2 + 3, "victim lost 2")
	end)

	t.test("passive revive triggers once", function()
		local phoenix = def("Phoenix", "Attack", { "t_wait", "t_wait", "t_wait" }, "t_phoenix", { HP = 100, DEF = 0 })
		local hitter = def("Hitter", "Attack", { "atk_ult", "t_wait", "t_wait" }, nil, { ATK = 900 })
		local s = battle({ unit(phoenix), unit(idle), unit(idle) }, { unit(hitter), unit(idle), unit(idle) })
		s.Teams[2].Energy = 10
		assert(s:Submit(1, waitAll()))
		assert(s:Submit(2, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		local events = s:Resolve()
		t.equal(#eventsOf(events, "Revive"), 1)
		local revived = s.Teams[1].Units[1]
		t.truthy(revived.Alive, "back on its feet")
		t.equal(revived.HP, 25)
		t.truthy(revived.ReviveUsed)
		s.Teams[2].Energy = 10
		assert(s:Submit(1, waitAll()))
		assert(s:Submit(2, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		s:Resolve()
		t.falsy(revived.Alive, "second knockout is final")
	end)

	t.test("revive skill brings back a fallen ally once", function()
		local medic = def("Medic", "Support", { "t_revive", "t_wait", "t_wait" })
		local s = battle({ unit(medic), unit(idle), unit(idle) }, { unit(idle), unit(idle), unit(idle) })
		s.Teams[1].Units[2].HP = 0
		s.Teams[1].Units[2].Alive = false
		assert(s:Submit(1, { [1] = { Skill = 1 }, [3] = { Skill = 1 } }))
		assert(s:Submit(2, waitAll()))
		local revive = eventsOf(s:Resolve(), "Revive")
		t.equal(#revive, 1)
		t.equal(revive[1].Slot, 2)
		t.equal(s.Teams[1].Units[2].HP, math.floor(s.Teams[1].Units[2].MaxHP * 0.4 + 0.5))
	end)

	t.test("follow-up hits only targets below the threshold", function()
		local finisher = def("Finisher", "Attack", { "t_finisher", "t_wait", "t_wait" })
		local s = battle({ unit(finisher), unit(idle), unit(idle) }, { unit(idle), unit(idle), unit(idle) })
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, waitAll()))
		t.equal(#eventsOf(s:Resolve(), "FollowUp"), 0, "healthy target: no follow-up")
		s.Teams[2].Units[1].HP = math.floor(s.Teams[2].Units[1].MaxHP * 0.3)
		assert(s:Submit(1, { { Skill = 1, Target = 1 }, { Skill = 1 }, { Skill = 1 } }))
		assert(s:Submit(2, waitAll()))
		t.equal(#eventsOf(s:Resolve(), "FollowUp"), 1, "low target: follow-up")
	end)
end

-- Balance simulator: `lune run tools/sim [gamesPerMatchup]`
-- 1. Time-to-kill: Attack unit's 3.0x skill vs each class (roadmap targets).
-- 2. AI-vs-AI battles across every 3-class team: rounds per battle and class win rates.
-- Gate (Phase 1): TTK within +/-0.5 hits of target, mean rounds 5-8, no class above 60%.
local process = require("@lune/process")

local Rng = require("../src/shared/Util/Rng")
local Stats = require("../src/shared/Combat/Stats")
local BattleSession = require("../src/shared/Combat/BattleSession")
local BattleAI = require("../src/shared/Combat/BattleAI")
local Classes = require("../src/shared/Content/Classes")

local GAMES = tonumber(process.args[1]) or 100
local CLASS_ORDER = { "Attack", "Defense", "Support", "Disrupt", "Speed" }
local KIT = {
	Attack = { Skills = { "atk_basic", "atk_skill", "atk_ult" } },
	Defense = { Skills = { "def_basic", "def_skill", "def_ult" }, Passive = "thorned_guard" },
	Support = { Skills = { "sup_basic", "sup_skill", "sup_ult" } },
	Disrupt = { Skills = { "dis_basic", "dis_skill", "dis_ult" } },
	Speed = { Skills = { "spd_basic", "spd_skill", "spd_ult" }, Passive = "riposte" },
}
local TTK_TARGET = { Defense = 4, Support = 3, Disrupt = 2.5, Attack = 2.5, Speed = 1.5 }

local function template(class)
	return {
		Id = "Sim" .. class,
		Name = class,
		Rarity = 5,
		Class = class,
		Stats = Classes.statsFor(class, 5),
		Speed = Classes.speedFor(class, 5),
		EnergyRegen = Classes.Templates[class].EnergyRegen,
		Skills = KIT[class].Skills,
		Passive = KIT[class].Passive,
	}
end

local defs = {}
for _, class in CLASS_ORDER do
	defs[class] = template(class)
end

-- 1. Time to kill -------------------------------------------------------------------
print("== Time to kill: Attack 3.0x skill, 5-star vs 5-star")
local rng = Rng.new(1234)
local attacker = defs.Attack.Stats
local ttkPass = true
for _, class in CLASS_ORDER do
	local target = defs[class].Stats
	local trials, totalHits = 10000, 0
	for _ = 1, trials do
		local hp, hits = target.HP, 0
		while hp > 0 do
			local crit = rng:chance(attacker.CritRate)
			hp -= Stats.damage(attacker.ATK, 3.0, target.DEF, if crit then attacker.CritDamage else 1)
			hits += 1
		end
		totalHits += hits
	end
	local mean = totalHits / trials
	local ok = math.abs(mean - TTK_TARGET[class]) <= 0.5
	ttkPass = ttkPass and ok
	print(
		string.format(
			"  %-8s HP %4d DEF %3d  hits %.2f  target %.1f  %s",
			class,
			target.HP,
			target.DEF,
			mean,
			TTK_TARGET[class],
			if ok then "ok" else "OFF"
		)
	)
end

-- 2. Battles ------------------------------------------------------------------------
local comps = {}
for a = 1, 5 do
	for b = a + 1, 5 do
		for c = b + 1, 5 do
			table.insert(comps, { CLASS_ORDER[a], CLASS_ORDER[b], CLASS_ORDER[c] })
		end
	end
end

local function loadout(comp)
	local team = {}
	for i, class in comp do
		team[i] = { Character = defs[class], Items = {} }
	end
	return team
end

local rounds = {}
local draws, games = 0, 0
local classWins, classGames = {}, {}
local compWins, compGames = {}, {}
local endReasons = {}
local seed = 1
for i, compA in comps do
	for j, compB in comps do
		for _ = 1, GAMES do
			seed += 1
			local session = BattleSession.new({ Seed = seed, Teams = { loadout(compA), loadout(compB) } })
			local aiRng = Rng.new(seed * 7919)
			while session.Phase ~= "Finished" do
				assert(session:Submit(1, BattleAI.choose(session, 1, aiRng, { Randomness = 0.15 })))
				assert(session:Submit(2, BattleAI.choose(session, 2, aiRng, { Randomness = 0.15 })))
				session:Resolve()
			end
			games += 1
			table.insert(rounds, session.Round)
			endReasons[session.EndReason] = (endReasons[session.EndReason] or 0) + 1
			if session.Winner == 0 then
				draws += 1
			end
			local function record(comp, side, compKey)
				local won = session.Winner == side
				compGames[compKey] = (compGames[compKey] or 0) + 1
				compWins[compKey] = (compWins[compKey] or 0) + (if won then 1 else 0)
				local other = if side == 1 then compB else compA
				for _, class in comp do
					if not table.find(other, class) then
						classGames[class] = (classGames[class] or 0) + 1
						classWins[class] = (classWins[class] or 0) + (if won then 1 else 0)
					end
				end
			end
			if i ~= j then
				record(compA, 1, table.concat(compA, "/"))
				record(compB, 2, table.concat(compB, "/"))
			end
		end
	end
end

table.sort(rounds)
local sum = 0
for _, r in rounds do
	sum += r
end
local mean = sum / #rounds
local function pct(p)
	return rounds[math.max(1, math.floor(#rounds * p))]
end
print(string.format("\n== %d battles (%d per matchup, AI randomness 0.15)", games, GAMES))
print(
	string.format(
		"  rounds: mean %.2f  median %d  p10 %d  p90 %d  draws %.1f%%",
		mean,
		pct(0.5),
		pct(0.1),
		pct(0.9),
		draws / games * 100
	)
)
for reason, count in endReasons do
	print(string.format("  ended by %s: %.1f%%", reason, count / games * 100))
end
local roundsPass = mean >= 5 and mean <= 8

print("\n== Class win rate (games where only one side has the class)")
local classPass = true
for _, class in CLASS_ORDER do
	local rate = (classWins[class] or 0) / math.max(1, classGames[class] or 0)
	local ok = rate <= 0.60 and rate >= 0.40
	classPass = classPass and rate <= 0.60
	print(string.format("  %-8s %.1f%%  %s", class, rate * 100, if ok then "ok" else "CHECK"))
end

print("\n== Team comps (non-mirror)")
local compList = {}
for key, n in compGames do
	table.insert(compList, { Key = key, Rate = compWins[key] / n })
end
table.sort(compList, function(a, b)
	return a.Rate > b.Rate
end)
for _, entry in compList do
	print(string.format("  %-26s %.1f%%", entry.Key, entry.Rate * 100))
end

print(
	string.format(
		"\nGATE: TTK %s | rounds %s | class balance %s",
		if ttkPass then "PASS" else "FAIL",
		if roundsPass then "PASS" else "FAIL",
		if classPass then "PASS" else "FAIL"
	)
)

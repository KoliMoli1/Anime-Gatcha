-- Phase 5 summon rules: odds, soft pity, 4-star guarantee, selector ticket, items and shards.
local Summon = require("../src/shared/Rules/Summon")
local Schema = require("../src/shared/Rules/ProfileSchema")
local Banners = require("../src/shared/Content/Banners")
local Characters = require("../src/shared/Content/Characters")
local Items = require("../src/shared/Content/Items")
local Rng = require("../src/shared/Util/Rng")

local banner = Banners.ById.launch_1
local NOW = 1_800_000_000

local function total(lines)
	local sum = 0
	for _, line in lines do
		sum += line.Chance
	end
	return sum
end

local function chanceOf(lines, tier)
	for _, line in lines do
		if line.Tier == tier then
			return line.Chance
		end
	end
	return nil
end

return function(t)
	t.test("every banner's odds total 100% and only name real content", function()
		for _, b in Banners.List do
			t.near(total(Summon.odds(b, Summon.newPity(), Items)), 1, 1e-9, b.Id)
			for _, list in { b.Featured5, b.Featured4, b.Standard4 } do
				for _, id in list do
					t.truthy(Characters[id], `{b.Id}: {id} exists`)
				end
			end
			for _, id in b.Featured5 do
				t.equal(Characters[id].Rarity, 5, `{id} is a 5-star`)
			end
			for _, id in b.Standard4 do
				t.equal(Characters[id].Rarity, 4, `{id} is a 4-star`)
			end
		end
	end)

	t.test("an empty featured 4-star slot hands its share to the standard 4-stars", function()
		local lines = Summon.odds(banner, Summon.newPity(), Items)
		t.equal(#banner.Featured4, 0)
		t.equal(chanceOf(lines, "Featured4"), 0)
		t.near(chanceOf(lines, "Standard4"), 0.035, 1e-9)
		t.near(chanceOf(lines, "Featured5"), 0.005, 1e-9)
	end)

	t.test("soft pity adds 3% per summon from the 120th and keeps the total at 100%", function()
		local pity = Summon.newPity()
		pity.SinceFive = 118
		t.near(chanceOf(Summon.odds(banner, pity, Items), "Featured5"), 0.005, 1e-9, "119th summon")
		pity.SinceFive = 119
		local lines = Summon.odds(banner, pity, Items)
		t.near(chanceOf(lines, "Featured5"), 0.035, 1e-9, "120th summon")
		t.near(total(lines), 1, 1e-9)
		pity.SinceFive = 159
		t.near(chanceOf(Summon.odds(banner, pity, Items), "Featured5"), 1, 1e-9, "capped at 100%")
	end)

	t.test("a 4-star character or better at least every 10 summons", function()
		for seed = 1, 300 do
			local rng = Rng.new(seed)
			local pity = Summon.newPity()
			local results = Summon.many(rng, banner, pity, Items, 10)
			local best = 0
			for _, result in results do
				if result.Kind == "Character" then
					best = math.max(best, result.Rarity)
				end
			end
			t.truthy(best >= 4, `seed {seed} 10-summon has a 4-star character`)
		end
	end)

	t.test("selector ticket at 160 points; points carry over and survive a 5-star", function()
		local rng = Rng.new(7)
		local pity = Summon.newPity()
		local _, tickets = Summon.many(rng, banner, pity, Items, 159)
		t.equal(tickets, 0)
		t.equal(pity.Points, 159)
		local _, ticket = Summon.roll(rng, banner, pity, Items)
		t.truthy(ticket, "160th summon earns the ticket")
		t.equal(pity.Points, 0)
		local _, more = Summon.many(rng, banner, pity, Items, 320)
		t.equal(more, 2)
	end)

	t.test("a 5-star resets soft pity but not pity points", function()
		local pity = Summon.newPity()
		pity.SinceFive = 158
		pity.Points = 70
		local result = Summon.roll(Rng.new(3), banner, pity, Items)
		t.equal(result.Rarity, 5, "soft pity forces the 5-star")
		t.equal(pity.SinceFive, 0)
		t.equal(pity.Points, 71)
	end)

	t.test("drop rates match the published odds", function()
		local rng = Rng.new(2026)
		local counts = {}
		local trials = 200000
		for _ = 1, trials do
			-- Fresh pity each time so neither pity rule bends the base rates.
			local result = Summon.roll(rng, banner, Summon.newPity(), Items)
			counts[result.Tier] = (counts[result.Tier] or 0) + 1
		end
		local expected = Summon.odds(banner, Summon.newPity(), Items)
		for _, line in expected do
			local seen = (counts[line.Tier] or 0) / trials
			-- 4 standard errors.
			local tolerance = 4 * math.sqrt(line.Chance * (1 - line.Chance) / trials) + 1e-9
			t.near(seen, line.Chance, tolerance, line.Tier)
		end
	end)

	t.test("players see a 5-star well before the selector ticket on average", function()
		local rng = Rng.new(99)
		local runs, sum, worst = 2000, 0, 0
		for _ = 1, runs do
			local pity = Summon.newPity()
			local n = 0
			repeat
				n += 1
				local result = Summon.roll(rng, banner, pity, Items)
			until result.Rarity == 5 and result.Kind == "Character"
			sum += n
			worst = math.max(worst, n)
		end
		t.truthy(worst <= Summon.SELECTOR_PITY, `worst case {worst} within 160`)
		t.truthy(sum / runs < 130, `mean {sum / runs}`)
	end)

	t.test("duplicate items turn into shards", function()
		local data = Schema.default(NOW, Characters)
		local item = Items.hunter_ring
		t.equal(Schema.grantItem(data, item, NOW), "New")
		local kind, shards = Schema.grantItem(data, item, NOW)
		t.equal(kind, "Duplicate")
		t.equal(shards, 3)
		t.equal(data.Shards, 3)
	end)

	t.test("sanitize repairs old pity and caps the summon history", function()
		local data = Schema.default(NOW, Characters)
		data.Pity = { Character = 12, Bad = { Points = -4, SinceFive = 3 } } :: any
		data.SelectorTickets = { Character = -1 }
		for i = 1, Schema.HISTORY_SIZE + 7 do
			table.insert(
				data.SummonHistory,
				{ At = i, Banner = "launch_1", Kind = "Item", Id = "worn_band", Rarity = 1 }
			)
		end
		Schema.sanitize(data, NOW, Characters, Items)
		t.equal(data.Pity.Character.Points, 0)
		t.equal(data.Pity.Bad.Points, 0)
		t.equal(data.Pity.Bad.SinceFive, 3)
		t.equal(data.SelectorTickets.Character, 0)
		t.equal(#data.SummonHistory, Schema.HISTORY_SIZE)
		t.equal(data.SummonHistory[1].At, 8, "oldest entries dropped")
	end)

	t.test("restricted players can only spend earned gems", function()
		local data = Schema.default(NOW, Characters)
		data.Gems = { Paid = 5000, Earned = 50 }
		t.falsy(Schema.spendEarnedGems(data, 100))
		data.Gems.Earned = 150
		t.truthy(Schema.spendEarnedGems(data, 100))
		t.equal(data.Gems.Paid, 5000)
	end)
end

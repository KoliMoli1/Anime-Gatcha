--!strict
-- Summon banners (roadmap Phase 5). One new banner each month (Phase 10).
-- Odds come from the roadmap's "Gacha and economy numbers" and must total 100%.
-- Banners in the same PityGroup share pity, so pity carries over between monthly banners.

export type Odds = {
	Featured5: number,
	Featured4: number,
	Standard4: number,
	Item3: number,
	Item2: number,
	Item1: number,
}

export type Banner = {
	Id: string,
	Name: string,
	PityGroup: string,
	-- Unix seconds; 0 / math.huge = always on.
	StartsAt: number,
	EndsAt: number,
	-- Featured 5-star characters. The selector ticket picks one of these.
	Featured5: { string },
	-- Featured 4-star characters (side banner). Empty until the team designs them:
	-- their share then falls to the standard 4-star pool.
	Featured4: { string },
	-- Off-banner 4-star characters.
	Standard4: { string },
	Odds: Odds,
}

local Banners = {}

Banners.DEFAULT_ODDS = table.freeze({
	Featured5 = 0.005,
	Featured4 = 0.010,
	Standard4 = 0.025,
	Item3 = 0.16,
	Item2 = 0.30,
	Item1 = 0.50,
}) :: Odds

Banners.List = {
	{
		Id = "launch_1",
		Name = "City Awakens",
		PityGroup = "Character",
		StartsAt = 0,
		EndsAt = math.huge,
		Featured5 = { "Boku", "Kojo" },
		Featured4 = {},
		Standard4 = { "TrainingAttack", "TrainingDefense", "TrainingSupport", "TrainingSpeed", "TrainingDisrupt" },
		Odds = Banners.DEFAULT_ODDS,
	},
} :: { Banner }

Banners.ById = {} :: { [string]: Banner }
for _, banner in Banners.List do
	Banners.ById[banner.Id] = banner
end

-- Banners open at this time, in list order.
function Banners.active(now: number): { Banner }
	local open = {}
	for _, banner in Banners.List do
		if now >= banner.StartsAt and now < banner.EndsAt then
			table.insert(open, banner)
		end
	end
	return open
end

return Banners

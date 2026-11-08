--!nonstrict
-- Banner summons (roadmap Phase 5). All rolls happen here with server-side RNG; the client
-- only ever sees results. Every summon is written to the player's SummonHistory and the
-- server log (audit trail).
--
-- Remotes:
--   GetSummonState() -> { Banners, Gems, Tickets, Restricted }  (live, pity-adjusted odds)
--   Summon(bannerId, count 1|10) -> { success, message?, Results, Tickets, TicketsEarned, Gems, Banner }
--   RedeemSelector(bannerId, characterId) -> { success, message?, Result }
--   Roll() -> legacy single summon on the first open banner (keeps the interim Summon panel working)
--   SummonStateUpdated (server -> client): same shape as GetSummonState
--
-- Policy: players with ArePaidRandomItemsRestricted can only summon with earned Gems.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local t = require(ReplicatedStorage.Packages.t)
local Banners = require(Shared.Content.Banners)
local Characters = require(Shared.Content.Characters)
local Items = require(Shared.Content.Items)
local Summon = require(Shared.Rules.Summon)
local Schema = require(Shared.Rules.ProfileSchema)
local Rng = require(Shared.Util.Rng)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)

local GachaService = {}

GachaService.COOLDOWN = 0.75

local rng = Rng.new(Random.new():NextInteger(1, 2 ^ 30))
local lastSummonAt: { [Player]: number } = {}
local restricted: { [Player]: boolean } = {}
local stateUpdated = Net.event("SummonStateUpdated")

-- Studio testers can force the restricted path with the player attribute "PolicyRestricted".
local function isRestricted(player: Player): boolean
	local forced = player:GetAttribute("PolicyRestricted")
	if forced ~= nil then
		return forced == true
	end
	local cached = restricted[player]
	if cached ~= nil then
		return cached
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	-- If the lookup fails, be safe and treat the player as restricted.
	local value = not ok or (type(info) == "table" and info.ArePaidRandomItemsRestricted == true)
	restricted[player] = value
	return value
end

local function nameOf(kind: string, id: string): string
	local def = if kind == "Character" then Characters[id] else Items[id]
	return def and def.Name or id
end

local function namesOf(ids: { string })
	local names = {}
	for index, id in ids do
		names[index] = { Id = id, Name = nameOf("Character", id) }
	end
	return names
end

function GachaService.State(player: Player)
	local data = ProfileService.Get(player)
	if not data then
		return { Loaded = false }
	end
	local banners = {}
	for _, banner in Banners.active(os.time()) do
		local pity = data.Pity[banner.PityGroup] or Summon.newPity()
		table.insert(banners, {
			Id = banner.Id,
			Name = banner.Name,
			PityGroup = banner.PityGroup,
			EndsAt = if banner.EndsAt == math.huge then nil else banner.EndsAt,
			Featured5 = namesOf(banner.Featured5),
			Featured4 = namesOf(banner.Featured4),
			Standard4 = namesOf(banner.Standard4),
			Odds = Summon.odds(banner, pity, Items),
			Pity = { Points = pity.Points, SinceFive = pity.SinceFive, SinceFour = pity.SinceFour },
			SelectorAt = Summon.SELECTOR_PITY,
			SoftPityFrom = Summon.SOFT_PITY_START,
			FourStarDue = Summon.fourStarDue(pity),
		})
	end
	local restrictedNow = isRestricted(player)
	return {
		Loaded = true,
		Banners = banners,
		Cost = Summon.COST,
		MultiCount = Summon.MULTI_COUNT,
		Gems = if restrictedNow then data.Gems.Earned else Schema.totalGems(data),
		Tickets = table.clone(data.SelectorTickets),
		Restricted = restrictedNow,
	}
end

local function publish(player: Player)
	stateUpdated:FireClient(player, GachaService.State(player))
end

local function grant(data, result, now: number)
	if result.Kind == "Character" then
		local outcome, coins = Schema.grantCharacter(data, Characters[result.Id], now)
		return { Outcome = outcome, CosmeticCoins = coins }
	end
	local outcome, shards = Schema.grantItem(data, Items[result.Id], now)
	return { Outcome = outcome, Shards = shards }
end

-- Spends, rolls and grants inside one profile update, so a failure leaves nothing half-done.
function GachaService.Summon(player: Player, bannerId: string, count: number)
	local banner = Banners.ById[bannerId]
	local now = os.time()
	if not banner or now < banner.StartsAt or now >= banner.EndsAt then
		return { success = false, message = "That banner is not open." }
	end
	if count ~= 1 and count ~= Summon.MULTI_COUNT then
		return { success = false, message = "Invalid summon count." }
	end
	local clock = os.clock()
	if clock - (lastSummonAt[player] or -math.huge) < GachaService.COOLDOWN then
		return { success = false, message = "Please wait a moment." }
	end
	lastSummonAt[player] = clock
	local restrictedNow = isRestricted(player)
	local _, response = ProfileService.Update(player, function(data)
		local cost = Summon.cost(count)
		local paid = if restrictedNow then Schema.spendEarnedGems(data, cost) else Schema.spendGems(data, cost)
		if not paid then
			return false,
				{
					success = false,
					message = if restrictedNow
						then "Not enough earned Gems. In your region, summons use earned Gems only."
						else "Not enough Gems!",
				}
		end
		local pity = Schema.pityFor(data, banner.PityGroup)
		local results, tickets = Summon.many(rng, banner, pity, Items, count)
		if tickets > 0 then
			data.SelectorTickets[banner.PityGroup] = (data.SelectorTickets[banner.PityGroup] or 0) + tickets
		end
		local shown = {}
		for index, result in results do
			local granted = grant(data, result, now)
			Schema.recordSummon(
				data,
				{ At = now, Banner = banner.Id, Kind = result.Kind, Id = result.Id, Rarity = result.Rarity }
			)
			shown[index] = {
				Kind = result.Kind,
				Id = result.Id,
				Name = nameOf(result.Kind, result.Id),
				Rarity = result.Rarity,
				Tier = result.Tier,
				Guaranteed = result.Guaranteed,
				Outcome = granted.Outcome,
				CosmeticCoins = granted.CosmeticCoins,
				Shards = granted.Shards,
			}
		end
		local pulled = {}
		for _, result in results do
			table.insert(pulled, `{result.Id}({result.Rarity})`)
		end
		print(
			string.format(
				"[Summon] %d %s x%d paidAllowed=%s pity=%d since5=%d tickets+%d :: %s",
				player.UserId,
				banner.Id,
				count,
				tostring(not restrictedNow),
				pity.Points,
				pity.SinceFive,
				tickets,
				table.concat(pulled, ",")
			)
		)
		return true,
			{
				success = true,
				Banner = banner.Id,
				Results = shown,
				TicketsEarned = tickets,
				Tickets = table.clone(data.SelectorTickets),
				Gems = if restrictedNow then data.Gems.Earned else Schema.totalGems(data),
			}
	end)
	if type(response) ~= "table" then
		return { success = false, message = "Your profile is still loading." }
	end
	if response.success then
		task.defer(publish, player)
	end
	return response
end

-- Spends one selector ticket of the banner's PityGroup on a featured 5-star of that banner.
function GachaService.RedeemSelector(player: Player, bannerId: string, characterId: string)
	local banner = Banners.ById[bannerId]
	if not banner or not table.find(banner.Featured5, characterId) then
		return { success = false, message = "Pick a featured 5-star from this banner." }
	end
	local _, response = ProfileService.Update(player, function(data)
		local have = data.SelectorTickets[banner.PityGroup] or 0
		if have < 1 then
			return false, { success = false, message = "You have no selector ticket." }
		end
		data.SelectorTickets[banner.PityGroup] = have - 1
		local outcome, coins = Schema.grantCharacter(data, Characters[characterId], os.time())
		print(string.format("[Summon] %d selector %s -> %s", player.UserId, banner.Id, characterId))
		return true,
			{
				success = true,
				Result = {
					Kind = "Character",
					Id = characterId,
					Name = nameOf("Character", characterId),
					Rarity = 5,
					Outcome = outcome,
					CosmeticCoins = coins,
				},
			}
	end)
	if type(response) ~= "table" then
		return { success = false, message = "Your profile is still loading." }
	end
	if response.success then
		task.defer(publish, player)
	end
	return response
end

-- Legacy single summon in the old response shape (success, characterId, characterName,
-- outcome, cosmeticCoins, coins, cost) for the interim Summon panel.
local function legacyRoll(player: Player)
	local banner = Banners.active(os.time())[1]
	if not banner then
		return { success = false, message = "No banner is open." }
	end
	local response = GachaService.Summon(player, banner.Id, 1)
	if not response.success then
		return { success = false, message = response.message, cost = Summon.COST }
	end
	local result = response.Results[1]
	return {
		success = true,
		characterId = if result.Kind == "Character" then result.Id else nil,
		itemId = if result.Kind == "Item" then result.Id else nil,
		characterName = result.Name,
		rarity = result.Rarity,
		outcome = if result.Kind == "Item" and result.Outcome == "Duplicate" then "Overflow" else result.Outcome,
		duplicate = result.Outcome ~= "New",
		collectionAdded = result.Outcome == "New",
		cosmeticCoins = result.CosmeticCoins or result.Shards,
		coins = response.Gems,
		cost = Summon.COST,
	}
end

function GachaService.Start()
	Net.handle("GetSummonState", { Rate = 2 }, GachaService.State)
	Net.handle("Summon", { Rate = 2, Burst = 2, Validate = t.tuple(t.string, t.integer) }, GachaService.Summon)
	Net.handle(
		"RedeemSelector",
		{ Rate = 1, Burst = 2, Validate = t.tuple(t.string, t.string) },
		GachaService.RedeemSelector
	)
	Net.handle("Roll", { Rate = 2, Burst = 2 }, legacyRoll)
	ProfileService.OnLoaded(publish)
	Players.PlayerRemoving:Connect(function(player)
		lastSummonAt[player] = nil
		restricted[player] = nil
	end)
end

return GachaService

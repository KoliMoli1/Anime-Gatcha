--!nonstrict
-- Collection and team select. Snapshot fields keep the prototype menus working
-- until Phase 2 replaces them (DisplayName, Classes, BaseStats, Count).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local t = require(ReplicatedStorage.Packages.t)
local Characters = require(Shared.Content.Characters)
local Items = require(Shared.Content.Items)
local Loadout = require(Shared.Rules.Loadout)
local Schema = require(Shared.Rules.ProfileSchema)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)

local RosterService = {}

local collectionUpdated = Net.event("CollectionUpdated")
local profileUpdated = Net.event("ProfileUpdated")

local function entryFor(id: string, owned)
	local def = Characters[id]
	return {
		Id = id,
		DisplayName = def.Name,
		Name = def.Name,
		Rarity = def.Rarity,
		Class = def.Class,
		Classes = { [def.Class] = true },
		Dupes = owned.Dupes,
		Count = 1 + owned.Dupes,
		Capacity = Loadout.capacity(def.Rarity, owned.Dupes),
		FirstObtainedAt = owned.ObtainedAt,
		SpeedRange = { Min = def.Speed.Min, Max = def.Speed.Max },
		Stats = table.clone(def.Stats),
		BaseStats = {
			MaxHealth = def.Stats.HP,
			Attack = def.Stats.ATK,
			Defense = def.Stats.DEF,
			Speed = def.Speed.Max,
			CritChance = def.Stats.CritRate,
			CritDamage = def.Stats.CritDamage,
			Effectiveness = def.Stats.EFF,
			Resistance = def.Stats.RES,
		},
	}
end

function RosterService.Collection(player: Player)
	local data = ProfileService.Get(player)
	if not data then
		return {}
	end
	local result = {}
	for id, owned in data.Characters do
		if Characters[id] then
			table.insert(result, entryFor(id, owned))
		end
	end
	table.sort(result, function(a, b)
		if a.Rarity == b.Rarity then
			return a.Id < b.Id
		end
		return a.Rarity > b.Rarity
	end)
	return result
end

local function teamIds(data): { string }
	local ids = {}
	for index, slot in data.Team do
		ids[index] = slot.Id
	end
	return ids
end

function RosterService.ProfileSnapshot(player: Player)
	local data = ProfileService.Get(player)
	if not data then
		return { Loaded = false }
	end
	local ownedItems = {}
	for id in data.Items do
		local item = Items[id]
		if item then
			table.insert(ownedItems, {
				Id = id,
				Name = item.Name,
				Stars = item.Stars,
				Value = Loadout.itemValue(item),
				Description = item.Description,
			})
		end
	end
	return {
		Loaded = true,
		Version = data.Version,
		Gems = Schema.totalGems(data),
		Coins = Schema.totalGems(data),
		CosmeticCoins = data.CosmeticCoins,
		Shards = data.Shards,
		OwnedCharacters = RosterService.Collection(player),
		OwnedItems = ownedItems,
		SelectedTeam = teamIds(data),
		Team = data.Team,
	}
end

local function publish(player: Player)
	collectionUpdated:FireClient(player, RosterService.Collection(player))
	profileUpdated:FireClient(player, RosterService.ProfileSnapshot(player))
end

-- Accepts either the prototype's {id, id, id} or {{Id, Items}, ...}.
local teamArg = t.union(
	t.strictArray(t.string, t.string, t.string),
	t.strictArray(
		t.strictInterface({ Id = t.string, Items = t.optional(t.array(t.string)) }),
		t.strictInterface({ Id = t.string, Items = t.optional(t.array(t.string)) }),
		t.strictInterface({ Id = t.string, Items = t.optional(t.array(t.string)) })
	)
)

function RosterService.SetTeam(player: Player, requested)
	return ProfileService.Update(player, function(data)
		local team = {}
		for index, entry in requested do
			if type(entry) == "string" then
				-- Old menu sends ids only: keep items the character already had equipped.
				local keep = {}
				for _, slot in data.Team do
					if slot.Id == entry then
						keep = table.clone(slot.Items)
					end
				end
				team[index] = { Id = entry, Items = keep }
			else
				team[index] = { Id = entry.Id, Items = table.clone(entry.Items or {}) }
			end
		end
		local ok, message = Loadout.validateTeam(team, data.Characters, data.Items, Characters, Items)
		if not ok then
			return false, { success = false, message = message }
		end
		data.Team = team
		return true, { success = true, SelectedTeam = teamIds(data), Team = team }
	end)
end

function RosterService.Start()
	Net.handle("GetCollectionSnapshot", { Rate = 2 }, function(player)
		return RosterService.Collection(player)
	end)
	Net.handle("GetProfileSnapshot", { Rate = 2 }, function(player)
		return RosterService.ProfileSnapshot(player)
	end)
	Net.handle("GetTeamSelectSnapshot", { Rate = 2 }, function(player)
		local data = ProfileService.Get(player)
		if not data then
			return { Loaded = false, OwnedCharacters = {}, SelectedTeam = {} }
		end
		return {
			Loaded = true,
			OwnedCharacters = RosterService.Collection(player),
			SelectedTeam = teamIds(data),
			Team = data.Team,
		}
	end)
	Net.handle("SetSelectedTeam", { Rate = 1, Burst = 3, Validate = teamArg }, function(player, requested)
		local _, result = RosterService.SetTeam(player, requested)
		if type(result) ~= "table" then
			return { success = false, message = "Your profile is still loading." }
		end
		return result
	end)
	ProfileService.OnLoaded(publish)
	ProfileService.OnChanged(publish)
end

return RosterService

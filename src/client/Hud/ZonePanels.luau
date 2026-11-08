--!nonstrict
-- The panel for the hub circle the player stands in (roadmap Phase 4: ZoneService).
-- Summon uses the interim single summon until Phase 5 brings banners, odds and pity.
-- PvP queues on the server as soon as the player steps in; this panel only shows status.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local HubZones = require(ReplicatedStorage.Shared.Content.HubZones)
local Characters = require(ReplicatedStorage.Shared.Content.Characters)
local GachaRules = require(ReplicatedStorage.Shared.Rules.GachaRules)
local State = require(script.Parent.Parent.Battle.BattleState)
local ProfileState = require(script.Parent.ProfileState)

local create = vide.create
local source = vide.source
local switch = vide.switch

local ZonePanels = {}

local function corner(radius: number)
	return create("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props do
		base[key] = value
	end
	return create("TextLabel")(base)
end

local function button(props)
	local base = {
		Size = UDim2.new(1, 0, 0, 48),
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = Theme.Panel,
		AutoButtonColor = true,
		corner(10),
	}
	for key, value in props do
		base[key] = value
	end
	return create("TextButton")(base)
end

-- Card shell: coloured title strip, then the body stacked vertically.
local function shell(zoneId: string, children)
	local zone = HubZones.ById[zoneId]
	return create("Frame")({
		Name = zoneId,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(400, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.08,
		corner(14),
		create("UIStroke")({ Color = zone.Color, Thickness = 2, Transparency = 0.2 }),
		create("UIPadding")({
			PaddingTop = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),
		create("UIListLayout")({ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		text({
			LayoutOrder = 0,
			Font = Enum.Font.GothamBlack,
			TextSize = 26,
			TextColor3 = zone.Color,
			Text = zone.Label,
		}),
		children,
	})
end

local function note(order: number, message: string)
	return text({
		LayoutOrder = order,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		Text = message,
	})
end

local function summonPanel()
	local remote = ReplicatedStorage.Remotes:WaitForChild("Roll") :: RemoteFunction
	local busy = source(false)
	local result = source(nil :: any)
	return shell("Summon", {
		text({
			LayoutOrder = 1,
			TextColor3 = Theme.Accent,
			Text = function()
				local profile = ProfileState.profile()
				return `Gems: {if profile then profile.Gems else "..."}   ·   {GachaRules.RollCost} per summon`
			end,
		}),
		create("Frame")({
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 74),
			BackgroundColor3 = Theme.PanelLight,
			corner(10),
			text({
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.fromScale(1, 1),
				TextSize = 18,
				RichText = true,
				Text = function()
					local r = result()
					if not r then
						return "Summon to pull a character."
					end
					if not r.success then
						return r.message or "Could not summon."
					end
					local def = Characters[r.characterId]
					local stars = def and string.rep("★", def.Rarity) or ""
					local outcome = if r.outcome == "New"
						then "NEW!"
						elseif r.outcome == "Duplicate" then "Duplicate: equip capacity up"
						else `Max duplicates: +{r.cosmeticCoins or 0} Cosmetic Coins`
					return `<b>{r.characterName}</b>  {stars}\n<font size="14">{outcome}</font>`
				end,
				TextColor3 = function()
					local r = result()
					local def = r and r.success and Characters[r.characterId]
					return if def then Theme.Class[def.Class] or Theme.Text else Theme.Text
				end,
			}),
		}),
		button({
			LayoutOrder = 3,
			BackgroundColor3 = HubZones.ById.Summon.Color,
			Text = function()
				return if busy() then "Summoning..." else "Summon x1"
			end,
			Activated = function()
				if busy() then
					return
				end
				busy(true)
				local ok, response = pcall(remote.InvokeServer, remote)
				busy(false)
				result(if ok and type(response) == "table" then response else { success = false })
			end,
		}),
		note(4, "Banners, odds and pity arrive with the full summon screen (Phase 5)."),
	})
end

local function pvpPanel()
	local remotes = ReplicatedStorage.Remotes
	local status = source("Joining the queue...")
	local queueSize = source(0)
	local connections = {}
	local function apply(snapshot)
		if type(snapshot) ~= "table" then
			return
		end
		if snapshot.Status then
			status(snapshot.Status)
		end
		if snapshot.QueueSize then
			queueSize(snapshot.QueueSize)
		end
	end
	table.insert(connections, (remotes:WaitForChild("PvPQueueUpdated") :: RemoteEvent).OnClientEvent:Connect(apply))
	table.insert(
		connections,
		(remotes:WaitForChild("PvPMatchFound") :: RemoteEvent).OnClientEvent:Connect(function(match)
			if type(match) == "table" then
				status(`Matched with {match.OpponentName}! {match.Status or ""}`)
			end
		end)
	)
	task.spawn(function()
		local remote = remotes:WaitForChild("GetPvPQueueSnapshot") :: RemoteFunction
		local ok, snapshot = pcall(remote.InvokeServer, remote)
		if ok then
			apply(snapshot)
		end
	end)
	vide.cleanup(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	return shell("PvP", {
		text({ LayoutOrder = 1, TextSize = 17, Text = status }),
		text({
			LayoutOrder = 2,
			TextColor3 = Theme.Accent,
			Text = function()
				return `Players searching on this server: {queueSize()}`
			end,
		}),
		note(3, "Step out of the circle to leave the queue. Live ranked battles arrive in Phase 6."),
	})
end

local function storyPanel()
	local remote = ReplicatedStorage.Remotes:WaitForChild("StartPracticeBattle") :: RemoteFunction
	local busy = source(false)
	local message = source("")
	return shell("Story", {
		text({
			LayoutOrder = 1,
			Text = "Chapter map arrives in Phase 7. Until then, train against the city's sparring team.",
		}),
		button({
			LayoutOrder = 2,
			BackgroundColor3 = HubZones.ById.Story.Color,
			TextColor3 = Theme.Text,
			Text = function()
				return if busy() then "Starting..." else "Practice Battle"
			end,
			Activated = function()
				if busy() then
					return
				end
				busy(true)
				message("")
				local ok, response = pcall(remote.InvokeServer, remote)
				busy(false)
				if not ok or type(response) ~= "table" or not response.success then
					message(
						if ok and type(response) == "table"
							then response.message or "Could not start."
							else "Could not start."
					)
				end
			end,
		}),
		text({ LayoutOrder = 3, TextSize = 13, TextColor3 = Theme.Bad, Text = message }),
	})
end

local function comingSoon(zoneId: string, body: string)
	return function()
		return shell(zoneId, {
			text({ LayoutOrder = 1, Text = body }),
		})
	end
end

function ZonePanels.create()
	return create("ScreenGui")({
		Name = "ZonePanels",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		Enabled = function()
			return State.phase() == "Idle"
		end,
		switch(ProfileState.zone)({
			Summon = summonPanel,
			PvP = pvpPanel,
			Story = storyPanel,
			Events = comingSoon("Events", "Limited-time events and raids arrive in Phase 8."),
			Shop = comingSoon("Shop", "Gem packs, the Shard Shop and cosmetics arrive in Phases 5 and 8."),
		}),
	})
end

return ZonePanels

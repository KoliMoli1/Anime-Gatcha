--!nonstrict
-- Team builder (roadmap Phase 4): pick 3 owned characters, then up to 3 items per
-- character within its Equip Capacity. The held-item slot unlocks in Phase 8.
-- Click a slot card to select it, a character to put it in that slot (swapping if it is
-- already on the team), an item to equip it there, and an equipped item to take it off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Characters = require(ReplicatedStorage.Shared.Content.Characters)
local Items = require(ReplicatedStorage.Shared.Content.Items)
local Loadout = require(ReplicatedStorage.Shared.Rules.Loadout)
local State = require(script.Parent.Parent.Battle.BattleState)
local ProfileState = require(script.Parent.ProfileState)

local create = vide.create
local source = vide.source
local effect = vide.effect
local untrack = vide.untrack

local TeamBuilder = {}

local function corner(radius: number)
	return create("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function padding(px: number)
	return create("UIPadding")({
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for key, value in props do
		base[key] = value
	end
	return create("TextLabel")(base)
end

local function stars(n: number): string
	return string.rep("★", n)
end

local function cloneTeam(team)
	local copy = {}
	for index = 1, Loadout.TEAM_SIZE do
		local slot = team and team[index]
		copy[index] = { Id = slot and slot.Id or "", Items = if slot then table.clone(slot.Items or {}) else {} }
	end
	return copy
end

local function ownedMaps(profile)
	local characters, items = {}, {}
	for _, entry in profile.OwnedCharacters do
		characters[entry.Id] = { Dupes = entry.Dupes }
	end
	for _, entry in profile.OwnedItems do
		items[entry.Id] = true
	end
	return characters, items
end

local function capacityOf(id: string): number
	local owned = ProfileState.owned(id)
	return if owned then owned.Capacity else 0
end

local function usedCapacity(slot): number
	local used = 0
	for _, itemId in slot.Items do
		local item = Items[itemId]
		if item then
			used += Loadout.itemValue(item)
		end
	end
	return used
end

-- open: Vide source toggled by the HUD's Team button.
function TeamBuilder.create(open: (boolean?) -> boolean)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetSelectedTeam") :: RemoteFunction
	local draft = source(cloneTeam(nil))
	local selectedSlot = source(1)
	local message = source("")
	local messageColor = source(Theme.TextDim)
	local saving = source(false)

	local function say(value: string, good: boolean?)
		message(value)
		messageColor(if good then Theme.Good else Theme.Bad)
	end

	-- Reload the saved team every time the screen opens.
	effect(function()
		if open() then
			local profile = untrack(ProfileState.profile)
			draft(cloneTeam(profile and profile.Team))
			selectedSlot(1)
			message("")
		end
	end)

	local function update(mutator)
		local team = cloneTeam(draft())
		mutator(team)
		draft(team)
	end

	local function assignCharacter(id: string)
		local target = selectedSlot()
		update(function(team)
			for index, slot in team do
				if slot.Id == id and index ~= target then
					-- Already on the team: swap the two slots, items travel with their character.
					team[index], team[target] = team[target], team[index]
					return
				end
			end
			team[target].Id = id
		end)
		message("")
	end

	local function equip(itemId: string)
		local target = selectedSlot()
		local team = draft()
		local slot = team[target]
		if slot.Id == "" then
			say("Put a character in this slot first.")
			return
		end
		if table.find(slot.Items, itemId) then
			return
		end
		if #slot.Items >= Loadout.ITEM_SLOTS then
			say("This character already has 3 items. Click one to take it off.")
			return
		end
		local value = Loadout.itemValue(Items[itemId])
		if usedCapacity(slot) + value > capacityOf(slot.Id) then
			say("Not enough Equip Capacity. Duplicates of this character raise it.")
			return
		end
		update(function(copy)
			for _, other in copy do
				local at = table.find(other.Items, itemId)
				if at then
					table.remove(other.Items, at)
				end
			end
			table.insert(copy[target].Items, itemId)
		end)
		message("")
	end

	local function unequip(index: number, itemId: string)
		update(function(team)
			local at = table.find(team[index].Items, itemId)
			if at then
				table.remove(team[index].Items, at)
			end
		end)
	end

	local function save()
		local profile = ProfileState.profile()
		if not profile or saving() then
			return
		end
		local team = draft()
		local ownedCharacters, ownedItems = ownedMaps(profile)
		local ok, reason = Loadout.validateTeam(team, ownedCharacters, ownedItems, Characters, Items)
		if not ok then
			say(reason or "That team is not valid.")
			return
		end
		saving(true)
		local payload = {}
		for index, slot in team do
			payload[index] = { Id = slot.Id, Items = slot.Items }
		end
		local success, response = pcall(remote.InvokeServer, remote, payload)
		saving(false)
		if success and type(response) == "table" and response.success then
			say("Team saved.", true)
		else
			say(
				if success and type(response) == "table"
					then response.message or "Could not save."
					else "Could not save."
			)
		end
	end

	local function slotCard(index: number)
		return create("TextButton")({
			Name = `Slot{index}`,
			LayoutOrder = index,
			Size = UDim2.new(1 / 3, -8, 1, 0),
			BackgroundColor3 = Theme.PanelLight,
			AutoButtonColor = false,
			Text = "",
			corner(10),
			create("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Thickness = 3,
				Color = Theme.Accent,
				Transparency = function()
					return if selectedSlot() == index then 0 else 1
				end,
			}),
			Activated = function()
				selectedSlot(index)
			end,
			function()
				local slot = draft()[index]
				local def = Characters[slot.Id]
				local color = if def then Theme.Class[def.Class] or Theme.Text else Theme.TextDim
				local capacity = if def then capacityOf(slot.Id) else 0
				local used = usedCapacity(slot)
				local children = {
					create("Frame")({
						Size = UDim2.new(1, 0, 0, 40),
						BackgroundColor3 = color,
						BackgroundTransparency = 0.25,
						corner(10),
						text({
							Position = UDim2.fromOffset(12, 0),
							Size = UDim2.new(1, -24, 1, 0),
							Font = Enum.Font.GothamBlack,
							TextSize = 18,
							TextColor3 = Theme.Panel,
							Text = if def then `{def.Name}  {stars(def.Rarity)}` else `Slot {index}: pick a character`,
						}),
					}),
					text({
						Position = UDim2.fromOffset(12, 46),
						Size = UDim2.new(1, -24, 0, 18),
						TextSize = 13,
						TextColor3 = if used > capacity then Theme.Bad else Theme.TextDim,
						Text = if def then `{def.Class}  ·  Equip Capacity {used}/{capacity}` else "",
					}),
					create("Frame")({
						Position = UDim2.fromOffset(12, 68),
						Size = UDim2.new(1, -24, 0, 6),
						BackgroundColor3 = Theme.Panel,
						corner(3),
						create("Frame")({
							Size = UDim2.fromScale(if capacity > 0 then math.clamp(used / capacity, 0, 1) else 0, 1),
							BackgroundColor3 = if used > capacity then Theme.Bad else Theme.Accent,
							corner(3),
						}),
					}),
				}
				for itemIndex = 1, Loadout.ITEM_SLOTS do
					local itemId = slot.Items[itemIndex]
					local item = itemId and Items[itemId]
					table.insert(
						children,
						create("TextButton")({
							Position = UDim2.fromOffset(12, 82 + (itemIndex - 1) * 32),
							Size = UDim2.new(1, -24, 0, 28),
							BackgroundColor3 = if item then Theme.Panel else Theme.PanelLight,
							BackgroundTransparency = if item then 0 else 0.4,
							Font = Enum.Font.GothamBold,
							TextSize = 13,
							TextColor3 = if item then Theme.Text else Theme.TextDim,
							Text = if item
								then `{item.Name} {stars(item.Stars)}  (-{Loadout.itemValue(item)})   ✕`
								else "+ item slot",
							corner(6),
							Activated = function()
								selectedSlot(index)
								if itemId then
									unequip(index, itemId)
								end
							end,
						})
					)
				end
				table.insert(
					children,
					text({
						Position = UDim2.fromOffset(12, 82 + Loadout.ITEM_SLOTS * 32),
						Size = UDim2.new(1, -24, 0, 24),
						TextSize = 12,
						Font = Enum.Font.Gotham,
						TextColor3 = Theme.TextDim,
						Text = "🔒 Held item slot unlocks with held items (Phase 8)",
					})
				)
				return children
			end,
		})
	end

	local function slotOf(team, id: string): number?
		for index, slot in team do
			if slot.Id == id then
				return index
			end
		end
		return nil
	end

	local function characterGrid()
		local profile = ProfileState.profile()
		local team = draft()
		local tiles = {}
		if not profile then
			return text({ Size = UDim2.new(1, 0, 0, 24), Text = "Loading your collection..." })
		end
		for order, entry in profile.OwnedCharacters do
			local def = Characters[entry.Id]
			if def then
				local inSlot = slotOf(team, entry.Id)
				local color = Theme.Class[def.Class] or Theme.Text
				table.insert(
					tiles,
					create("TextButton")({
						LayoutOrder = order,
						BackgroundColor3 = Theme.Panel,
						AutoButtonColor = true,
						Text = "",
						corner(8),
						create("UIStroke")({
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
							Color = color,
							Thickness = 2,
							Transparency = if inSlot then 0 else 0.6,
						}),
						create("Frame")({
							Size = UDim2.new(0, 6, 1, 0),
							BackgroundColor3 = color,
							BorderSizePixel = 0,
							corner(3),
						}),
						text({
							Position = UDim2.fromOffset(14, 6),
							Size = UDim2.new(1, -20, 0, 20),
							Font = Enum.Font.GothamBlack,
							TextSize = 15,
							Text = def.Name,
						}),
						text({
							Position = UDim2.fromOffset(14, 28),
							Size = UDim2.new(1, -20, 0, 16),
							TextSize = 12,
							TextColor3 = color,
							Text = `{stars(def.Rarity)} {def.Class}`,
						}),
						text({
							Position = UDim2.fromOffset(14, 46),
							Size = UDim2.new(1, -20, 0, 14),
							TextSize = 11,
							Font = Enum.Font.Gotham,
							TextColor3 = if inSlot then Theme.Accent else Theme.TextDim,
							Text = if inSlot
								then `In slot {inSlot}`
								else `Dupes {entry.Dupes}  ·  Cap {entry.Capacity}`,
						}),
						Activated = function()
							assignCharacter(entry.Id)
						end,
					})
				)
			end
		end
		return tiles
	end

	local function itemList()
		local profile = ProfileState.profile()
		local team = draft()
		if not profile then
			return {}
		end
		if #profile.OwnedItems == 0 then
			return text({
				Size = UDim2.new(1, 0, 0, 40),
				TextWrapped = true,
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.TextDim,
				Text = "No items yet. Items drop from story, events and ranked play.",
			})
		end
		local rows = {}
		local sorted = table.clone(profile.OwnedItems)
		table.sort(sorted, function(a, b)
			if a.Stars ~= b.Stars then
				return a.Stars > b.Stars
			end
			return a.Name < b.Name
		end)
		for order, entry in sorted do
			local holder = nil
			for index, slot in team do
				if table.find(slot.Items, entry.Id) then
					holder = index
				end
			end
			local holderName = holder and Characters[team[holder].Id] and Characters[team[holder].Id].Name
			table.insert(
				rows,
				create("TextButton")({
					LayoutOrder = order,
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundColor3 = Theme.Panel,
					AutoButtonColor = true,
					Text = "",
					corner(8),
					text({
						Position = UDim2.fromOffset(10, 4),
						Size = UDim2.new(1, -110, 0, 18),
						Text = `{entry.Name} {stars(entry.Stars)}`,
					}),
					text({
						Position = UDim2.fromOffset(10, 23),
						Size = UDim2.new(1, -110, 0, 16),
						TextSize = 12,
						Font = Enum.Font.Gotham,
						TextColor3 = Theme.TextDim,
						Text = entry.Description or "",
					}),
					text({
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -10, 0, 4),
						Size = UDim2.fromOffset(96, 18),
						TextXAlignment = Enum.TextXAlignment.Right,
						TextColor3 = Theme.Accent,
						Text = `Cost {entry.Value}`,
					}),
					text({
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -10, 0, 23),
						Size = UDim2.fromOffset(96, 16),
						TextXAlignment = Enum.TextXAlignment.Right,
						TextSize = 11,
						TextColor3 = Theme.Good,
						Text = holderName or "",
					}),
					Activated = function()
						equip(entry.Id)
					end,
				})
			)
		end
		return rows
	end

	local function section(props, title: string, children)
		local base = {
			BackgroundColor3 = Theme.PanelLight,
			BackgroundTransparency = 0.3,
			corner(10),
			text({
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -24, 0, 22),
				Font = Enum.Font.GothamBlack,
				TextSize = 16,
				Text = title,
			}),
			children,
		}
		for key, value in props do
			base[key] = value
		end
		return create("Frame")(base)
	end

	return create("ScreenGui")({
		Name = "TeamBuilder",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		Enabled = function()
			return open() and State.phase() == "Idle"
		end,
		create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			Active = true,
			create("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -32, 1, -32),
				BackgroundColor3 = Theme.Panel,
				corner(12),
				padding(14),
				create("UISizeConstraint")({ MaxSize = Vector2.new(1180, 740) }),
				text({
					Size = UDim2.fromOffset(200, 36),
					Font = Enum.Font.GothamBlack,
					TextSize = 24,
					TextColor3 = Theme.Accent,
					Text = "Your Team",
				}),
				text({
					Position = UDim2.fromOffset(170, 0),
					Size = UDim2.new(1, -400, 0, 36),
					TextSize = 14,
					TextColor3 = messageColor,
					Text = message,
				}),
				create("TextButton")({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -54, 0, 0),
					Size = UDim2.fromOffset(150, 36),
					BackgroundColor3 = Theme.Good,
					Font = Enum.Font.GothamBlack,
					TextSize = 17,
					TextColor3 = Theme.Panel,
					Text = function()
						return if saving() then "Saving..." else "Save Team"
					end,
					corner(8),
					Activated = save,
				}),
				create("TextButton")({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromOffset(44, 36),
					BackgroundColor3 = Theme.Bad,
					Font = Enum.Font.GothamBlack,
					TextSize = 18,
					TextColor3 = Theme.Text,
					Text = "X",
					corner(8),
					Activated = function()
						open(false)
					end,
				}),
				create("Frame")({
					Name = "Slots",
					Position = UDim2.fromOffset(0, 48),
					Size = UDim2.new(1, 0, 0, 212),
					BackgroundTransparency = 1,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 12),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					slotCard(1),
					slotCard(2),
					slotCard(3),
				}),
				section(
					{
						Name = "Characters",
						Position = UDim2.fromOffset(0, 272),
						Size = UDim2.new(0.6, -6, 1, -272),
					},
					"Characters  ·  click to place in the selected slot",
					{
						create("ScrollingFrame")({
							Position = UDim2.fromOffset(10, 38),
							Size = UDim2.new(1, -20, 1, -46),
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ScrollBarThickness = 5,
							CanvasSize = UDim2.new(),
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							ScrollingDirection = Enum.ScrollingDirection.Y,
							create("UIGridLayout")({
								CellSize = UDim2.fromOffset(170, 66),
								CellPadding = UDim2.fromOffset(8, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							characterGrid,
						}),
					}
				),
				section(
					{
						Name = "Items",
						Position = UDim2.new(0.6, 6, 0, 272),
						Size = UDim2.new(0.4, -6, 1, -272),
					},
					"Items  ·  click to equip",
					{
						create("ScrollingFrame")({
							Position = UDim2.fromOffset(10, 38),
							Size = UDim2.new(1, -20, 1, -46),
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ScrollBarThickness = 5,
							CanvasSize = UDim2.new(),
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							ScrollingDirection = Enum.ScrollingDirection.Y,
							create("UIListLayout")({ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
							itemList,
						}),
					}
				),
			}),
		}),
	})
end

return TeamBuilder

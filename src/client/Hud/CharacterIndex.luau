--!nonstrict
-- Collection screen (roadmap Phase 4): every character, filtered by rarity, class and
-- ownership. Pick one to see its stats and pie chart on the left, its combat model in the
-- middle and its kit on the right. Placeholder styling until Phase A.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Characters = require(ReplicatedStorage.Shared.Content.Characters)
local SkillContent = require(ReplicatedStorage.Shared.Content.Skills)
local KitForms = require(ReplicatedStorage.Shared.Content.KitForms)
local State = require(script.Parent.Parent.Battle.BattleState)
local StatPie = require(script.Parent.Parent.Battle.StatPie)
local ProfileState = require(script.Parent.ProfileState)

local create = vide.create
local source = vide.source
local switch = vide.switch

local CharacterIndex = {}

local CAMERA_FOV = 40

-- Highest rarity first, then by name.
local function roster(): { string }
	local ids = {}
	for id in Characters do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ca, cb = Characters[a], Characters[b]
		if ca.Rarity ~= cb.Rarity then
			return ca.Rarity > cb.Rarity
		end
		return ca.Name < cb.Name
	end)
	return ids
end

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
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props do
		base[key] = value
	end
	return create("TextLabel")(base)
end

local function column(props, children)
	local base = {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		corner(8),
		padding(10),
		create("UIListLayout")({ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		children,
	}
	for key, value in props do
		base[key] = value
	end
	return create("ScrollingFrame")(base)
end

local function percent(value: number): string
	return `{math.floor(value * 100 + 0.5)}%`
end

-- One stat line: colored square and name on the left, value on the right.
local function statRow(order: number, name: string, value: string, color: Color3)
	return create("Frame")({
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		text({
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(0.6, 1),
			TextColor3 = color,
			Text = `■ {name}`,
		}),
		text({
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromScale(0.6, 0),
			Size = UDim2.fromScale(0.4, 1),
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = value,
		}),
	})
end

local function statsColumn(def)
	local stats = def.Stats
	local values = {
		HP = stats.HP,
		ATK = stats.ATK,
		DEF = stats.DEF,
		SPD = def.Speed.Max,
		CritRate = stats.CritRate,
		CritDamage = stats.CritDamage,
		EFF = stats.EFF,
		RES = stats.RES,
	}
	return column({
		Name = "Stats",
		Size = UDim2.new(0.3, -8, 1, 0),
	}, {
		text({ LayoutOrder = 1, Font = Enum.Font.GothamBlack, TextSize = 24, Text = def.Name }),
		text({
			LayoutOrder = 2,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Theme.Class[def.Class] or Theme.Text,
			Text = `{def.Rarity}★ {def.Class}`,
		}),
		text({
			LayoutOrder = 3,
			TextSize = 12,
			TextColor3 = function()
				return if ProfileState.owned(def.Id) then Theme.Good else Theme.TextDim
			end,
			Text = function()
				local owned = ProfileState.owned(def.Id)
				if not owned then
					return "Not owned yet"
				end
				return `Owned  ·  {owned.Dupes} duplicates  ·  Equip Capacity {owned.Capacity}`
			end,
		}),
		create("Frame")({
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 150),
			BackgroundTransparency = 1,
			StatPie.create(function()
				return values
			end, 146),
		}),
		statRow(5, "HP", tostring(stats.HP), Theme.Stat.HP),
		statRow(6, "ATK", tostring(stats.ATK), Theme.Stat.ATK),
		statRow(7, "DEF", tostring(stats.DEF), Theme.Stat.DEF),
		statRow(8, "Speed", `{def.Speed.Min}–{def.Speed.Max}`, Theme.Stat.SPD),
		statRow(9, "Crit rate", percent(stats.CritRate), Theme.Stat.CritRate),
		statRow(10, "Crit damage", string.format("%.2fx", stats.CritDamage), Theme.Stat.CritDamage),
		statRow(11, "Effectiveness", percent(stats.EFF), Theme.Stat.EFF),
		statRow(12, "Resistance", percent(stats.RES), Theme.Stat.RES),
		statRow(13, "Energy per round", `+{def.EnergyRegen}`, Theme.Accent),
	})
end

-- The combat rig for this class (ReplicatedStorage.UnitRigs, built by the server),
-- facing the camera.
local function modelView(def)
	local camera = create("Camera")({ FieldOfView = CAMERA_FOV })
	local viewport = create("ViewportFrame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(150, 150, 165),
		LightColor = Color3.fromRGB(255, 250, 240),
		-- Light travels from the camera side toward the model.
		LightDirection = Vector3.new(0.4, -0.8, 1),
		CurrentCamera = camera,
		camera,
		corner(8),
	})
	task.spawn(function()
		local rigs = ReplicatedStorage:WaitForChild("UnitRigs", 10)
		local template = rigs and rigs:FindFirstChild(def.Class)
		if not template then
			return
		end
		local model = template:Clone()
		-- Rigs face -Z at the identity pivot, so the camera looks back from -Z.
		model:PivotTo(CFrame.new())
		model.Parent = viewport
		local box, size = model:GetBoundingBox()
		local center = box.Position
		local distance = (size.Y / 2) / math.tan(math.rad(CAMERA_FOV / 2)) * 1.25
		camera.CFrame = CFrame.lookAt(center - Vector3.new(0, 0, distance), center)
	end)
	return create("Frame")({
		Name = "Model",
		Position = UDim2.fromScale(0.3, 0),
		Size = UDim2.new(0.38, -8, 1, 0),
		BackgroundTransparency = 1,
		viewport,
		text({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -8),
			Size = UDim2.new(1, -20, 0, 0),
			TextSize = 11,
			TextColor3 = Theme.TextDim,
			Text = "Combat model (placeholder until Phase A)",
		}),
	})
end

local function skillMeta(skill): string
	local parts = { skill.Kind, if skill.Cost == 0 then "Free" else `{skill.Cost} energy` }
	if skill.Cooldown then
		table.insert(parts, `{skill.Cooldown}-round cooldown`)
	end
	return table.concat(parts, "  ·  ")
end

local function card(order: number, title: string, meta: string?, body: string)
	return create("Frame")({
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.2,
		corner(6),
		padding(8),
		create("UIListLayout")({ Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		text({ LayoutOrder = 1, Font = Enum.Font.GothamBold, TextSize = 14, Text = title }),
		if meta then text({ LayoutOrder = 2, TextSize = 12, TextColor3 = Theme.Accent, Text = meta }) else nil,
		text({ LayoutOrder = 3, TextSize = 12, TextColor3 = Theme.TextDim, Text = body }),
	})
end

local function heading(order: number, label: string)
	return text({ LayoutOrder = order, Font = Enum.Font.GothamBlack, TextSize = 16, Text = label })
end

local function kitColumn(def)
	local children = {}
	local order = 0
	local function add(child)
		order += 1
		child.LayoutOrder = order
		table.insert(children, child)
	end
	add(heading(0, "Abilities"))
	for index, id in def.Skills do
		local skill = SkillContent.Skills[id]
		if skill then
			add(card(0, `{index}. {skill.Name}`, skillMeta(skill), skill.Description or ""))
		end
	end
	local passive = def.Passive and SkillContent.Passives[def.Passive]
	if passive then
		add(heading(0, "Passive"))
		add(card(0, passive.Name, nil, passive.Description or ""))
	end
	local form = def.Kit and KitForms[def.Kit]
	if form then
		add(heading(0, form.Label))
		for index, id in form.Skills do
			local skill = SkillContent.Skills[id]
			if skill then
				local title = if #form.Skills > 1 then `{index}. {skill.Name}` else skill.Name
				add(card(0, title, skillMeta(skill), skill.Description or ""))
			end
		end
	end
	return column({
		Name = "Kit",
		Position = UDim2.fromScale(0.68, 0),
		Size = UDim2.fromScale(0.32, 1),
	}, children)
end

local function detail(def)
	return create("Frame")({
		Name = def.Id,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		statsColumn(def),
		modelView(def),
		kitColumn(def),
	})
end

-- open: Vide source toggled by the main menu's Characters button.
function CharacterIndex.create(open: (boolean?) -> boolean)
	local ids = roster()
	local selected = source(ids[1])
	-- Filters: 0 = any rarity, "All" = any class.
	local rarityFilter = source(0)
	local classFilter = source("All")
	local ownedOnly = source(false)
	local function matches(id: string): boolean
		local def = Characters[id]
		return (rarityFilter() == 0 or def.Rarity == rarityFilter())
			and (classFilter() == "All" or def.Class == classFilter())
			and (not ownedOnly() or ProfileState.owned(id) ~= nil)
	end

	local function chip(order: number, label: string, isOn: () -> boolean, onClick: () -> (), color: Color3?)
		return create("TextButton")({
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = function()
				return if isOn() then color or Theme.Accent else Theme.PanelLight
			end,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = function()
				return if isOn() then Theme.Panel else Theme.Text
			end,
			Text = label,
			corner(6),
			create("UIPadding")({ PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
			Activated = onClick,
		})
	end

	local filterChips = {}
	local function addChip(...)
		table.insert(filterChips, chip(#filterChips + 1, ...))
	end
	for _, rarity in { 0, 5, 4, 3 } do
		addChip(if rarity == 0 then "All ★" else `{rarity}★`, function()
			return rarityFilter() == rarity
		end, function()
			rarityFilter(rarity)
		end)
	end
	for _, class in { "All", "Attack", "Defense", "Support", "Disrupt", "Speed" } do
		addChip(if class == "All" then "All classes" else class, function()
			return classFilter() == class
		end, function()
			classFilter(class)
		end, Theme.Class[class])
	end
	addChip("Owned only", ownedOnly, function()
		ownedOnly(not ownedOnly())
	end, Theme.Good)
	local views = {}
	for _, id in ids do
		views[id] = function()
			return detail(Characters[id])
		end
	end

	local buttons = {}
	for index, id in ids do
		local def = Characters[id]
		buttons[index] = create("TextButton")({
			LayoutOrder = index,
			Visible = function()
				return matches(id)
			end,
			Size = UDim2.fromOffset(140, 34),
			BackgroundColor3 = function()
				return if selected() == id then Theme.Accent else Theme.PanelLight
			end,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = function()
				return if selected() == id then Theme.Panel else Theme.Text
			end,
			Text = function()
				return if ProfileState.owned(id)
					then `{def.Name} {def.Rarity}★`
					else `{def.Name} {def.Rarity}★ 🔒`
			end,
			corner(6),
			Activated = function()
				selected(id)
			end,
		})
	end

	return create("ScreenGui")({
		Name = "CharacterIndex",
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
				padding(12),
				create("UISizeConstraint")({ MaxSize = Vector2.new(1240, 720) }),
				text({
					AutomaticSize = Enum.AutomaticSize.None,
					Size = UDim2.fromOffset(150, 34),
					Font = Enum.Font.GothamBlack,
					TextSize = 20,
					TextColor3 = Theme.Accent,
					Text = "Collection",
				}),
				create("Frame")({
					Name = "Filters",
					Position = UDim2.fromOffset(0, 46),
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					filterChips,
				}),
				create("ScrollingFrame")({
					Position = UDim2.fromOffset(160, 0),
					Size = UDim2.new(1, -214, 0, 42),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollBarThickness = 4,
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					ScrollingDirection = Enum.ScrollingDirection.X,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					buttons,
				}),
				create("TextButton")({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromOffset(44, 34),
					BackgroundColor3 = Theme.Bad,
					Font = Enum.Font.GothamBlack,
					TextSize = 18,
					TextColor3 = Theme.Text,
					Text = "X",
					corner(6),
					Activated = function()
						open(false)
					end,
				}),
				create("Frame")({
					Name = "Body",
					Position = UDim2.fromOffset(0, 88),
					Size = UDim2.new(1, 0, 1, -88),
					BackgroundTransparency = 1,
					switch(selected)(views),
				}),
			}),
		}),
	})
end

return CharacterIndex

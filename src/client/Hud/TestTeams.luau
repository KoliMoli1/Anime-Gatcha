--!nonstrict
-- Playtest team picker (Studio and group admins only): choose any three units for each
-- side and start a test battle against the AI. The server re-checks admin rights.
-- Left click a slot for the next character, right click for the previous one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Characters = require(ReplicatedStorage.Shared.Content.Characters)

local create = vide.create
local source = vide.source

local TestTeams = {}

-- Highest rarity first, then by name, so the new 5-stars come up first.
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

local function allowed(): boolean
	return RunService:IsStudio() or Players.LocalPlayer:GetAttribute("IsAdmin") == true
end

-- Builds the panel; call inside a vide root.
function TestTeams.create(remote: RemoteFunction)
	local ids = roster()
	local function indexOf(id: string): number
		return table.find(ids, id) or 1
	end
	-- picks[side][slot] = index into ids
	local picks = source({
		{ indexOf("Boku"), indexOf("Kojo"), indexOf("Shade") },
		{ indexOf("Sasta"), indexOf("TrainingSupport"), indexOf("TrainingDisrupt") },
	})
	local message = source("")
	local busy = source(false)
	local visible = source(allowed())
	Players.LocalPlayer:GetAttributeChangedSignal("IsAdmin"):Connect(function()
		visible(allowed())
	end)

	local function step(side: number, slot: number, delta: number)
		local next = table.clone(picks())
		next[side] = table.clone(next[side])
		next[side][slot] = (next[side][slot] - 1 + delta) % #ids + 1
		picks(next)
	end

	local function slotButton(side: number, slot: number)
		return create("TextButton")({
			LayoutOrder = slot,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Theme.PanelLight,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Theme.Text,
			Text = function()
				local def = Characters[ids[picks()[side][slot]]]
				return `{slot}. {def.Name}  ·  {def.Rarity}★ {def.Class}`
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			Activated = function()
				step(side, slot, 1)
			end,
			MouseButton2Click = function()
				step(side, slot, -1)
			end,
		})
	end

	local function column(side: number, title: string)
		return create("Frame")({
			LayoutOrder = side + 1,
			Size = UDim2.new(1, 0, 0, 122),
			BackgroundTransparency = 1,
			create("UIListLayout")({ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
			create("TextLabel")({
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if side == 1 then Theme.Good else Theme.Bad,
				Text = title,
			}),
			slotButton(side, 1),
			slotButton(side, 2),
			slotButton(side, 3),
		})
	end

	local function start()
		if busy() then
			return
		end
		busy(true)
		message("")
		local chosen = { {}, {} }
		for side = 1, 2 do
			for slot = 1, 3 do
				chosen[side][slot] = ids[picks()[side][slot]]
			end
		end
		local ok, response = pcall(remote.InvokeServer, remote, chosen[1], chosen[2])
		busy(false)
		if not ok or type(response) ~= "table" or not response.success then
			message(
				if ok and type(response) == "table" then response.message or "Could not start." else "Could not start."
			)
			task.delay(3, function()
				message("")
			end)
		end
	end

	return create("Frame")({
		Name = "TestTeams",
		AnchorPoint = Vector2.new(1, 1),
		-- Sits above the prototype gems counter in the bottom-right corner.
		Position = UDim2.new(1, -16, 1, -80),
		Size = UDim2.fromOffset(260, 360),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Visible = visible,
		create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
		create("UIPadding")({
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		create("UIListLayout")({ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("TextLabel")({
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.Accent,
			TextWrapped = true,
			RichText = true,
			Text = `Test Teams <font size="11" color="#aaaaaa">(click: next, right click: back)</font>`,
		}),
		column(1, "Your team"),
		column(2, "Enemy team (AI)"),
		create("TextButton")({
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = Color3.fromRGB(70, 120, 200),
			Font = Enum.Font.GothamBlack,
			TextSize = 16,
			TextColor3 = Theme.Text,
			Text = function()
				return if busy() then "Starting..." else "Start Test Battle"
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
			Activated = start,
		}),
		create("TextLabel")({
			LayoutOrder = 5,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Theme.Bad,
			TextWrapped = true,
			Text = message,
		}),
	})
end

return TestTeams

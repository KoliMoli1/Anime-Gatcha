--!nonstrict
-- Stat pie chart (deck: "stats displayed in a pie chart"). Each stat is scaled
-- against a reference value so different units compare fairly, and the slices
-- are drawn as stacked radial sectors. Placeholder look until Phase A.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)

local create = vide.create

local StatPie = {}

StatPie.ORDER = { "HP", "ATK", "DEF", "SPD", "CritRate", "CritDamage", "EFF", "RES" }
StatPie.LABEL = {
	HP = "HP",
	ATK = "ATK",
	DEF = "DEF",
	SPD = "Speed",
	CritRate = "Crit",
	CritDamage = "Crit DMG",
	EFF = "Effect.",
	RES = "Resist.",
}
local REFERENCE = { HP = 700, ATK = 130, DEF = 110, SPD = 100, CritRate = 0.4, CritDamage = 2.0, EFF = 0.5, RES = 0.5 }

-- values = { HP = ..., ATK = ..., ... } (CritRate etc. as fractions)
function StatPie.shares(values): { [string]: number }
	local weights, total = {}, 0
	for _, stat in StatPie.ORDER do
		local weight = math.clamp((values[stat] or 0) / REFERENCE[stat], 0.05, 1.5)
		weights[stat] = weight
		total += weight
	end
	for stat, weight in weights do
		weights[stat] = weight / total
	end
	return weights
end

-- Opaque on the left half of a circle, transparent on the right, with a hard edge.
local LEFT_OPAQUE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local RIGHT_OPAQUE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(0.501, 0),
	NumberSequenceKeypoint.new(1, 0),
})

-- One filled sector from 12 o'clock clockwise to `degrees()`, the standard Roblox
-- radial-fill technique: each half of the circle is clipped, and a hard-edged
-- gradient rotated inside it reveals the right amount of that half.
local function sector(color: () -> Color3, degrees: () -> number, zIndex: number)
	local function half(isRight: boolean)
		return create("Frame")({
			Position = UDim2.fromScale(if isRight then 0.5 else 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = zIndex,
			create("Frame")({
				Position = UDim2.fromScale(if isRight then -1 else 0, 0),
				Size = UDim2.fromScale(2, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				ZIndex = zIndex,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIGradient")({
					Transparency = if isRight then LEFT_OPAQUE else RIGHT_OPAQUE,
					Rotation = function()
						local angle = degrees()
						return if isRight then math.clamp(angle, 0, 180) else math.clamp(angle - 180, 0, 180)
					end,
				}),
			}),
		})
	end
	return create("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		half(true),
		half(false),
	})
end

-- statsSource: Vide source/derived function returning the values table (or nil).
-- Slices are stacked sectors: each stat's sector runs from 0 to its cumulative
-- share, and earlier stats sit on top, so each shows only its own slice.
function StatPie.create(statsSource: () -> any, size: number)
	local count = #StatPie.ORDER
	local layers = {}
	for index, stat in StatPie.ORDER do
		local cumulative = function()
			local values = statsSource()
			if not values then
				return if index == count then 360 else 0
			end
			local shares = StatPie.shares(values)
			local total = 0
			for i = 1, index do
				total += shares[StatPie.ORDER[i]]
			end
			return if index == count then 360 else total * 360
		end
		local color = function()
			return if statsSource() then Theme.Stat[stat] else Theme.PanelLight
		end
		layers[index] = sector(color, cumulative, 10 + count - index)
	end
	return create("Frame")({
		Name = "StatPie",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		layers,
		create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.42, 0.42),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			ZIndex = 30,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		}),
	})
end

-- Legend rows "■ ATK 120" for the same values.
function StatPie.legend(statsSource: () -> any)
	local rows = {}
	for index, stat in StatPie.ORDER do
		rows[index] = create("TextLabel")({
			LayoutOrder = index,
			Size = UDim2.new(0.5, -4, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Stat[stat],
			Text = function()
				local values = statsSource()
				if not values then
					return ""
				end
				local value = values[stat] or 0
				local shown = if stat == "CritRate"
						or stat == "EFF"
						or stat == "RES"
					then `{math.floor(value * 100 + 0.5)}`
					elseif stat == "CritDamage" then string.format("%.2fx", value)
					else tostring(math.floor(value + 0.5))
				return `■ {StatPie.LABEL[stat]} {shown}`
			end,
		})
	end
	return create("Frame")({
		Size = UDim2.new(1, 0, 0, 68),
		BackgroundTransparency = 1,
		create("UIGridLayout")({
			CellSize = UDim2.new(0.5, -4, 0, 16),
			CellPadding = UDim2.fromOffset(4, 1),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		rows,
	})
end

return StatPie

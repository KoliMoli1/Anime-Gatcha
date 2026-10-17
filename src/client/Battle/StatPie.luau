--!nonstrict
-- Stat pie chart (deck: "stats displayed in a pie chart"). Each stat is scaled
-- against a reference value so different units compare fairly, and the slices
-- are drawn as thin colored spokes around a center. Placeholder look until Phase A.

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
local SPOKES = 96

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

-- statsSource: Vide source/derived function returning the values table (or nil).
function StatPie.create(statsSource: () -> any, size: number)
	local radius = size / 2
	local spokeColor = function(index: number)
		return function()
			local values = statsSource()
			if not values then
				return Theme.PanelLight
			end
			local shares = StatPie.shares(values)
			local position = (index - 0.5) / SPOKES
			local running = 0
			for _, stat in StatPie.ORDER do
				running += shares[stat]
				if position <= running then
					return Theme.Stat[stat]
				end
			end
			return Theme.Stat.RES
		end
	end
	local spokes = {}
	for index = 1, SPOKES do
		-- GuiObjects rotate around their own center, so each spoke is a full-diameter
		-- transparent bar centered on the pie with only its top half colored.
		spokes[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(math.ceil(2 * math.pi * radius / SPOKES) + 1, size),
			Rotation = (index - 0.5) / SPOKES * 360,
			BackgroundTransparency = 1,
			create("Frame")({
				Size = UDim2.fromScale(1, 0.5),
				BorderSizePixel = 0,
				BackgroundColor3 = spokeColor(index),
			}),
		})
	end
	return create("Frame")({
		Name = "StatPie",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		spokes,
		create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size * 0.42, size * 0.42),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
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

--!nonstrict
-- Battle screen (Vide). Functional layout with placeholder styling:
-- top bar (round, timer, energy), unit info panel (stats, pie chart, skills),
-- planned moves + confirm, battle log, round banner and result screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local State = require(script.Parent.BattleState)
local StatPie = require(script.Parent.StatPie)

local create = vide.create
local source = vide.source
local derive = vide.derive
local show = vide.show

local BattleHud = {}

export type Actions = {
	chooseSkill: (slot: number, skill: number) -> (),
	confirm: () -> (),
	clear: () -> (),
	leave: () -> (),
}

local function corner(radius: number?)
	return create("UICorner")({ CornerRadius = UDim.new(0, radius or 8) })
end

local function padding(px: number)
	return create("UIPadding")({
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function label(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}
	for key, value in props do
		base[key] = value
	end
	return create("TextLabel")(base)
end

local function button(props)
	local base = {
		AutoButtonColor = true,
		BackgroundColor3 = Theme.PanelLight,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		corner(6),
	}
	for key, value in props do
		if type(key) == "number" then
			table.insert(base, value)
		else
			base[key] = value
		end
	end
	return create("TextButton")(base)
end

local function selectedUnit()
	local selected = State.selected()
	if not selected then
		return nil
	end
	return State.unit(selected.Side, selected.Slot), selected
end

local function pieValues()
	local unit = selectedUnit()
	if not unit then
		return nil
	end
	return {
		HP = unit.MaxHP,
		ATK = unit.Stats.ATK,
		DEF = unit.Stats.DEF,
		SPD = unit.SpeedRange.Max,
		CritRate = unit.Stats.CritRate,
		CritDamage = unit.Stats.CritDamage,
		EFF = unit.Stats.EFF,
		RES = unit.Stats.RES,
	}
end

local function turnsText(turns: number): string
	return if turns == 1 then "1 turn" else `{turns} turns`
end

local function effectLines(unit): string
	local lines = {}
	for _, effect in unit.Effects do
		if effect.Kind == "Taunt" then
			table.insert(lines, `Taunting ({turnsText(effect.Turns)})`)
		elseif effect.Kind == "Shield" then
			table.insert(lines, `Shield {effect.Amount} ({turnsText(effect.Turns)})`)
		elseif effect.Stat then
			local relative = effect.Stat == "ATK" or effect.Stat == "DEF" or effect.Stat == "SPD"
			local amount = math.floor(effect.Amount * 100 + 0.5)
			local text = if relative then `{amount}%` else `{amount}`
			if effect.Amount > 0 then
				text = "+" .. text
			end
			table.insert(lines, `{effect.Stat} {text} ({turnsText(effect.Turns)})`)
		end
	end
	return if #lines > 0 then table.concat(lines, "\n") else "No active effects"
end

local function skillButton(index: number, actions: Actions)
	local skillOf = function()
		local unit = selectedUnit()
		return unit and unit.Skills[index]
	end
	local ownChoosing = function()
		local unit, selected = selectedUnit()
		return unit ~= nil and selected.Side == State.side() and unit.Alive and State.phase() == "Choosing"
	end
	local chosen = function()
		local _, selected = selectedUnit()
		local action = selected and State.actions()[selected.Slot]
		return ownChoosing() and action ~= nil and action.Skill == index
	end
	-- Affordable if the energy left, plus whatever this unit's current pick costs, covers it.
	local affordable = function()
		local unit, selected = selectedUnit()
		local skill = unit and unit.Skills[index]
		if not skill or not selected then
			return false
		end
		local action = State.actions()[selected.Slot]
		local refund = if action then unit.Skills[action.Skill].Cost else 0
		return State.remainingEnergy() + refund >= skill.Cost
	end
	return button({
		LayoutOrder = 10 + index,
		Size = UDim2.new(1, 0, 0, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		Active = ownChoosing,
		AutoButtonColor = ownChoosing,
		BackgroundColor3 = function()
			if chosen() then
				return Color3.fromRGB(150, 115, 35)
			end
			if ownChoosing() and not affordable() then
				return Color3.fromRGB(70, 40, 44)
			end
			return if ownChoosing() then Theme.PanelLight else Theme.Panel
		end,
		TextColor3 = function()
			return if ownChoosing() and not affordable() and not chosen() then Theme.TextDim else Theme.Text
		end,
		Text = function()
			local skill = skillOf()
			if not skill then
				return ""
			end
			local warning = if ownChoosing()
					and not affordable()
					and not chosen()
				then "  ·  not enough energy"
				else ""
			return `  {skill.Name}  ·  {skill.Kind}  ·  {skill.Cost} energy{warning}\n  {skill.Description}`
		end,
		padding(4),
		Activated = function()
			local _, selected = selectedUnit()
			if ownChoosing() and selected then
				actions.chooseSkill(selected.Slot, index)
			end
		end,
	})
end

local function infoPanel(actions: Actions)
	return create("Frame")({
		Name = "InfoPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(310, 500),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Visible = function()
			return selectedUnit() ~= nil
		end,
		corner(10),
		padding(10),
		create("UIListLayout")({ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		label({
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 22),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			Text = function()
				local unit, selected = selectedUnit()
				if not unit then
					return ""
				end
				local owner = if selected.Side == State.side() then "Yours" else "Enemy"
				return `{unit.Name}  ({owner})`
			end,
		}),
		label({
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 16),
			TextColor3 = Theme.TextDim,
			Text = function()
				local unit = selectedUnit()
				if not unit then
					return ""
				end
				local hp = State.hp()[State.selected().Side]
				local current = hp and hp[State.selected().Slot] or unit.HP
				return `{unit.Rarity}-star {unit.Class}  ·  HP {current}/{unit.MaxHP}  ·  Speed {unit.SpeedRange.Min}-{unit.SpeedRange.Max}`
			end,
		}),
		create("Frame")({
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 120),
			BackgroundTransparency = 1,
			StatPie.create(pieValues, 116),
			create("Frame")({
				Position = UDim2.fromOffset(124, 0),
				Size = UDim2.new(1, -124, 1, 0),
				BackgroundTransparency = 1,
				label({
					Size = UDim2.fromScale(1, 1),
					TextSize = 12,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextColor3 = Theme.Accent,
					Text = function()
						local unit = selectedUnit()
						return if unit then effectLines(unit) else ""
					end,
				}),
			}),
		}),
		create("Frame")({
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 68),
			BackgroundTransparency = 1,
			StatPie.legend(pieValues),
		}),
		label({
			LayoutOrder = 5,
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = 12,
			TextColor3 = Theme.TextDim,
			Text = function()
				local unit = selectedUnit()
				if unit and unit.Passive then
					return `Passive: {unit.Passive.Name} — {unit.Passive.Description}`
				end
				return ""
			end,
		}),
		skillButton(1, actions),
		skillButton(2, actions),
		skillButton(3, actions),
	})
end

local function topBar(remaining)
	return create("Frame")({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(460, 62),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		corner(10),
		label({
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(0.5, -14, 0, 22),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			Text = function()
				local snapshot = State.snapshot()
				return if snapshot then `Round {snapshot.Round}` else ""
			end,
		}),
		label({
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(0.5, -14, 0, 22),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = function()
				return if remaining() <= 10 then Theme.Bad else Theme.Text
			end,
			Text = function()
				local phase = State.phase()
				if phase == "Choosing" then
					return `{remaining()}s to choose`
				elseif phase == "Waiting" then
					return "Waiting for opponent..."
				elseif phase == "Playback" then
					return "Resolving..."
				end
				return ""
			end,
		}),
		create("Frame")({
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -28, 0, 18),
			BackgroundColor3 = Color3.fromRGB(28, 32, 46),
			BorderSizePixel = 0,
			corner(5),
			-- Energy left after planned moves (solid) plus what they will spend (faded).
			create("Frame")({
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Stat.SPD,
				Size = function()
					local snapshot = State.snapshot()
					if not snapshot then
						return UDim2.fromScale(0, 1)
					end
					return UDim2.fromScale(math.max(0, State.remainingEnergy()) / snapshot.MaxEnergy, 1)
				end,
				corner(5),
			}),
			create("Frame")({
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Stat.CritRate,
				BackgroundTransparency = 0.55,
				Position = function()
					local snapshot = State.snapshot()
					if not snapshot then
						return UDim2.fromScale(0, 0)
					end
					return UDim2.fromScale(math.max(0, State.remainingEnergy()) / snapshot.MaxEnergy, 0)
				end,
				Size = function()
					local snapshot = State.snapshot()
					if not snapshot then
						return UDim2.fromScale(0, 1)
					end
					return UDim2.fromScale(State.plannedCost() / snapshot.MaxEnergy, 1)
				end,
				corner(5),
			}),
			label({
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextStrokeTransparency = 0.5,
				ZIndex = 2,
				Text = function()
					local snapshot = State.snapshot()
					if not snapshot then
						return ""
					end
					local planned = State.plannedCost()
					return `Energy {State.remainingEnergy()}/{snapshot.MaxEnergy}`
						.. (if planned > 0 then `   ·   {planned} planned` else "")
				end,
			}),
		}),
	})
end

local function actionBar(actions: Actions)
	local rows = {}
	for slot = 1, 3 do
		rows[slot] = label({
			LayoutOrder = slot,
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 13,
			Text = function()
				local unit = State.unit(State.side(), slot)
				if not unit then
					return ""
				end
				if not unit.Alive then
					return `{slot}. {unit.Name} — knocked out`
				end
				local action = State.actions()[slot]
				if not action then
					return `{slot}. {unit.Name} — choose a move`
				end
				local skill = unit.Skills[action.Skill]
				local text = `{slot}. {unit.Name} — {skill.Name}`
				if action.Target and (skill.Target == "Enemy" or skill.Target == "Ally") then
					local targetSide = if skill.Target == "Enemy" then 3 - State.side() else State.side()
					local target = State.unit(targetSide, action.Target)
					text ..= ` on {target and target.Name or "?"}`
				end
				return text
			end,
			TextColor3 = function()
				return if State.actions()[slot] then Theme.Good else Theme.Text
			end,
		})
	end
	return create("Frame")({
		Name = "ActionBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(560, 128),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Visible = function()
			local phase = State.phase()
			return phase == "Choosing" or phase == "Waiting"
		end,
		corner(10),
		padding(10),
		label({
			Size = UDim2.new(1, 0, 0, 18),
			TextColor3 = Theme.Accent,
			Font = Enum.Font.GothamBold,
			Text = function()
				return State.hint()
			end,
		}),
		create("Frame")({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, -150, 0, 60),
			BackgroundTransparency = 1,
			create("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder }),
			rows,
		}),
		button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 24),
			Size = UDim2.fromOffset(140, 44),
			TextSize = 16,
			Text = "Confirm turn",
			BackgroundColor3 = function()
				return if State.phase() == "Choosing" and State.allChosen()
					then Color3.fromRGB(60, 150, 90)
					else Theme.PanelLight
			end,
			Activated = function()
				actions.confirm()
			end,
		}),
		button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 74),
			Size = UDim2.fromOffset(140, 28),
			Text = "Clear moves",
			Activated = function()
				actions.clear()
			end,
		}),
	})
end

local function logPanel()
	return create("Frame")({
		Name = "LogPanel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(320, 230),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.25,
		corner(10),
		padding(8),
		label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 12,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Text = function()
				local lines = State.log()
				local first = math.max(1, #lines - 13)
				return table.concat(lines, "\n", first, #lines)
			end,
		}),
	})
end

local function banner()
	return label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(600, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack,
		TextSize = 46,
		TextStrokeTransparency = 0.3,
		Visible = function()
			return State.banner() ~= nil
		end,
		Text = function()
			return State.banner() or ""
		end,
	})
end

local function resultScreen(actions: Actions)
	return show(State.result, function(result)
		return create("Frame")({
			Name = "Result",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(380, 210),
			BackgroundColor3 = Theme.Panel,
			corner(12),
			padding(16),
			label({
				Size = UDim2.new(1, 0, 0, 50),
				TextXAlignment = Enum.TextXAlignment.Center,
				Font = Enum.Font.GothamBlack,
				TextSize = 40,
				TextColor3 = function()
					local outcome = result().Outcome
					return if outcome == "Win" then Theme.Good elseif outcome == "Loss" then Theme.Bad else Theme.Text
				end,
				Text = function()
					local outcome = result().Outcome
					return if outcome == "Win" then "VICTORY" elseif outcome == "Loss" then "DEFEAT" else "DRAW"
				end,
			}),
			label({
				Position = UDim2.fromOffset(0, 60),
				Size = UDim2.new(1, 0, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = function()
					return `+{result().Gems} gems`
				end,
			}),
			button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromOffset(200, 46),
				TextSize = 16,
				Text = "Leave arena",
				BackgroundColor3 = Color3.fromRGB(60, 120, 200),
				Activated = function()
					actions.leave()
				end,
			}),
		})
	end)
end

-- Builds the screen; returns the ScreenGui. Must run inside a Vide root.
function BattleHud.create(actions: Actions)
	local camera = workspace.CurrentCamera
	local scale = source(1)
	local function updateScale()
		local viewport = camera.ViewportSize
		scale(math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.55, 1.25))
	end
	updateScale()
	local viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	local now = source(workspace:GetServerTimeNow())
	local heartbeat = RunService.Heartbeat:Connect(function()
		now(workspace:GetServerTimeNow())
	end)
	local remaining = derive(function()
		return math.max(0, math.ceil(State.deadline() - now()))
	end)
	vide.cleanup(function()
		viewportConnection:Disconnect()
		heartbeat:Disconnect()
	end)

	-- UIScale shrinks from the top-left corner, so the wrapper is sized 1/scale
	-- to still cover the whole screen after scaling.
	local function scaled(child)
		return create("Frame")({
			Size = function()
				return UDim2.fromScale(1 / scale(), 1 / scale())
			end,
			BackgroundTransparency = 1,
			create("UIScale")({
				Scale = function()
					return scale()
				end,
			}),
			child,
		})
	end

	return create("ScreenGui")({
		Name = "BattleHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		Enabled = function()
			return State.phase() ~= "Idle"
		end,
		scaled(topBar(remaining)),
		scaled(infoPanel(actions)),
		scaled(actionBar(actions)),
		scaled(logPanel()),
		scaled(banner()),
		scaled(resultScreen(actions)),
		button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(110, 34),
			Text = "Forfeit",
			BackgroundColor3 = Color3.fromRGB(120, 50, 50),
			Visible = function()
				return State.phase() ~= "Finished"
			end,
			Activated = function()
				actions.leave()
			end,
		}),
	})
end

return BattleHud

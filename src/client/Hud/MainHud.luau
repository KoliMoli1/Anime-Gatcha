--!nonstrict
-- Hub HUD (roadmap Phase 4): gems, the Team and Collection buttons, and the Test Teams
-- picker for Studio playtests and admins. Modes (Summon, PvP, Story, ...) open from the
-- circles on the hub floor (ZonePanels), so there are no mode buttons here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local State = require(script.Parent.Parent.Battle.BattleState)
local ProfileState = require(script.Parent.ProfileState)
local TestTeams = require(script.Parent.TestTeams)
local CharacterIndex = require(script.Parent.CharacterIndex)
local TeamBuilder = require(script.Parent.TeamBuilder)
local ZonePanels = require(script.Parent.ZonePanels)

local create = vide.create
local source = vide.source

local MainHud = {}

local function corner(radius: number)
	return create("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function menuButton(order: number, label: string, color: Color3, onClick: () -> ())
	return create("TextButton")({
		LayoutOrder = order,
		Size = UDim2.fromOffset(150, 46),
		BackgroundColor3 = color,
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = Theme.Panel,
		Text = label,
		corner(10),
		create("UIStroke")({ Color = Theme.Panel, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Activated = onClick,
	})
end

function MainHud.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local testRemote = remotes:WaitForChild("StartTestBattle") :: RemoteFunction
	local indexOpen = source(false)
	local teamOpen = source(false)

	vide.root(function()
		create("ScreenGui")({
			Name = "MainHud",
			ResetOnSpawn = false,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
			Enabled = function()
				return State.phase() == "Idle"
			end,
			create("Frame")({
				Name = "Gems",
				Position = UDim2.fromOffset(16, 16),
				Size = UDim2.fromOffset(0, 40),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.15,
				corner(20),
				create("UIStroke")({ Color = Theme.Accent, Thickness = 2 }),
				create("UIPadding")({ PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
				create("TextLabel")({
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBlack,
					TextSize = 20,
					TextColor3 = Theme.Accent,
					Text = function()
						local profile = ProfileState.profile()
						return `💎 {if profile then profile.Gems else "..."}`
					end,
				}),
			}),
			create("Frame")({
				Name = "Menu",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 0),
				Size = UDim2.fromOffset(150, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				create("UIListLayout")({ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
				menuButton(1, "Team", Theme.Accent, function()
					indexOpen(false)
					teamOpen(true)
				end),
				menuButton(2, "Collection", Color3.fromRGB(120, 200, 255), function()
					teamOpen(false)
					indexOpen(true)
				end),
			}),
			create("TextLabel")({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 16),
				Size = UDim2.fromOffset(420, 24),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = Theme.Text,
				TextStrokeTransparency = 0.4,
				Visible = function()
					return ProfileState.zone() == nil
				end,
				Text = "Walk into a glowing circle to play",
			}),
			TestTeams.create(testRemote),
		})
		CharacterIndex.create(indexOpen)
		TeamBuilder.create(teamOpen)
		ZonePanels.create()
	end)
end

return MainHud

--!nonstrict
-- Temporary entry point until the hub circles (Phase 4): a Practice Battle button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local State = require(script.Parent.Parent.Battle.BattleState)

local create = vide.create
local source = vide.source

local MainHud = {}

function MainHud.Start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StartPracticeBattle")
	local message = source("")
	local busy = source(false)

	vide.root(function()
		create("ScreenGui")({
			Name = "MainHud",
			ResetOnSpawn = false,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
			Enabled = function()
				return State.phase() == "Idle"
			end,
			create("TextButton")({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -16),
				Size = UDim2.fromOffset(220, 54),
				BackgroundColor3 = Color3.fromRGB(190, 70, 70),
				Font = Enum.Font.GothamBlack,
				TextSize = 20,
				TextColor3 = Theme.Text,
				Text = function()
					return if busy() then "Starting..." else "Practice Battle"
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
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
						task.delay(3, function()
							message("")
						end)
					end
				end,
			}),
			create("TextLabel")({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -76),
				Size = UDim2.fromOffset(320, 20),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.Bad,
				TextStrokeTransparency = 0.5,
				Text = function()
					return message()
				end,
			}),
		})
	end)
end

return MainHud

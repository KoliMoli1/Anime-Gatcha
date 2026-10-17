local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local remote = ReplicatedStorage:WaitForChild("GenerateRandomNumber")
local player = Players.LocalPlayer
local gui = script.Parent
local panel = gui:WaitForChild("Panel")
local toggle = gui:WaitForChild("ToggleIcon")
local button = panel:WaitForChild("GenerateButton")
local result = panel:WaitForChild("Result")
local title = panel:WaitForChild("Title")
local balance = panel:WaitForChild("Balance")
local currencyHud = gui:WaitForChild("CurrencyHud")
title.Text = "Anime Gacha"
local normalPanelColor, normalResultColor, normalButtonColor = panel.BackgroundColor3, result.TextColor3, button.BackgroundColor3
local normalButtonText = "Roll for a Character"
button.Text = normalButtonText

local savedPanelPosition = panel.Position
local minimizedPosition = UDim2.new(savedPanelPosition.X.Scale, savedPanelPosition.X.Offset + panel.AbsoluteSize.X - 44, savedPanelPosition.Y.Scale, savedPanelPosition.Y.Offset)
local function updateTogglePosition()
	if panel.Visible then
		toggle.Position = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset + panel.AbsoluteSize.X - 44, panel.Position.Y.Scale, panel.Position.Y.Offset)
	else
		toggle.Position = minimizedPosition
	end
end

local function updateBalance(coins, cost)
	if coins ~= nil then
		balance.Text = string.format("🪙 Coins: %d | Cost: %d", coins, cost or 10)
		currencyHud.Text = string.format("🪙 Coins: %d", coins)
	end
end

-- Move the open window.
local panelDragging, panelInput, panelDragStart, panelStartPosition
panel.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		panelDragging, panelDragStart, panelStartPosition = true, input.Position, panel.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then panelDragging = false end end)
	end
end)
panel.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then panelInput = input end
end)

-- Move the minimized icon independently.
local iconDragging, iconInput, iconDragStart, iconStartPosition
local movedDuringIconDrag = false
if toggle:IsA("GuiButton") then toggle.Active = true end
toggle.InputBegan:Connect(function(input)
	if not panel.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		iconDragging, movedDuringIconDrag, iconDragStart, iconStartPosition = true, false, input.Position, toggle.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then iconDragging = false end end)
	end
end)
toggle.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then iconInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
	if input == panelInput and panelDragging then
		local d = input.Position - panelDragStart
		panel.Position = UDim2.new(panelStartPosition.X.Scale, panelStartPosition.X.Offset + d.X, panelStartPosition.Y.Scale, panelStartPosition.Y.Offset + d.Y)
		savedPanelPosition = panel.Position
		updateTogglePosition()
	elseif input == iconInput and iconDragging then
		local d = input.Position - iconDragStart
		if math.abs(d.X) + math.abs(d.Y) > 6 then movedDuringIconDrag = true end
		toggle.Position = UDim2.new(iconStartPosition.X.Scale, iconStartPosition.X.Offset + d.X, iconStartPosition.Y.Scale, iconStartPosition.Y.Offset + d.Y)
		minimizedPosition = toggle.Position
	end
end)

updateTogglePosition()
toggle.Activated:Connect(function()
	if movedDuringIconDrag then movedDuringIconDrag = false return end
	if panel.Visible then
		savedPanelPosition = panel.Position
		minimizedPosition = toggle.Position
		panel.Visible = false
		toggle.Text = "🎰"
	else
		panel.Position = UDim2.new(minimizedPosition.X.Scale, minimizedPosition.X.Offset - panel.AbsoluteSize.X + 44, minimizedPosition.Y.Scale, minimizedPosition.Y.Offset)
		savedPanelPosition = panel.Position
		panel.Visible = true
		toggle.Text = "🎲"
		updateTogglePosition()
	end
end)

local function celebrateHighRoll(number)
	result.Text = "⭐ " .. tostring(number) .. " ⭐"
	result.TextColor3 = Color3.fromRGB(255,220,45); button.BackgroundColor3 = Color3.fromRGB(220,150,25); panel.BackgroundColor3 = Color3.fromRGB(75,55,20); title.Text = "🎉 JACKPOT! 🎉"
	local character = player.Character or player.CharacterAdded:Wait(); local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local sparkles = Instance.new("Sparkles"); sparkles.SparkleColor = Color3.fromRGB(255,215,0); sparkles.Parent = root; Debris:AddItem(sparkles,5)
		local fire = Instance.new("Fire"); fire.Color = Color3.fromRGB(255,190,40); fire.SecondaryColor = Color3.fromRGB(255,80,10); fire.Size = 6; fire.Parent = root; Debris:AddItem(fire,3)
		local highlight = Instance.new("Highlight"); highlight.FillColor = Color3.fromRGB(255,210,35); highlight.OutlineColor = Color3.new(1,1,1); highlight.FillTransparency = .45; highlight.Parent = character; Debris:AddItem(highlight,5)
	end
	TweenService:Create(result,TweenInfo.new(.25,Enum.EasingStyle.Back),{TextSize=42}):Play(); task.wait(2.5); result.TextSize=32; result.TextColor3=normalResultColor; button.BackgroundColor3=normalButtonColor; panel.BackgroundColor3=normalPanelColor; title.Text="Anime Gacha"
end
button.Activated:Connect(function()
	button.Active = false; button.Text = "Rolling..."
	local ok, response = pcall(function() return remote:InvokeServer() end)
	if ok and type(response) == "table" then
		updateBalance(response.coins,response.cost)
		if response.success then if response.value >= 950 then celebrateHighRoll(response.value) else result.Text=tostring(response.value) end else result.Text=response.message or "Roll unavailable" end
	else result.Text="Error" end
	button.Text=normalButtonText; button.Active=true
end)
task.spawn(function()
	local coins = player:WaitForChild("leaderstats"):WaitForChild("Coins")
	local function refresh() updateBalance(coins.Value,10); button.Active = coins.Value >= 10 end
	coins:GetPropertyChangedSignal("Value"):Connect(refresh); refresh()
end)

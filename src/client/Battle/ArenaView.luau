--!nonstrict
-- The 3D side of the battle screen: camera, unit labels above heads, selection
-- highlights, floating numbers and clicking units. Placeholder visuals; Phase A
-- replaces the look.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(ReplicatedStorage.Shared.Theme)
local State = require(script.Parent.BattleState)

local create = vide.create

local ArenaView = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local destroyRoot: (() -> ())? = nil
local highlights: { Highlight } = {}
local inputConnection: RBXScriptConnection? = nil
local onUnitClicked: ((number, number) -> ())? = nil

function ArenaView.model(side: number, slot: number): Model?
	local id = State.battleId()
	local arenas = workspace:FindFirstChild("Arenas")
	local arena = id and arenas and arenas:FindFirstChild(`Arena_{id}`)
	local units = arena and arena:FindFirstChild("Units")
	local model: any = units and units:FindFirstChild(`{side}_{slot}`)
	return model
end

local function head(model: Model): BasePart?
	local part: any = model:FindFirstChild("Head") or model.PrimaryPart
	return part
end

local function setCamera()
	local center = State.center()
	local behind = if State.side() == 1 then 1 else -1
	camera.CameraType = Enum.CameraType.Scriptable
	-- High enough to look over the player standing behind their team.
	local eye = center * CFrame.new(0, 34, 36 * behind)
	camera.CFrame = CFrame.lookAt(eye.Position, (center * CFrame.new(0, 0, -3 * behind)).Position)
end

local function effectSummary(unit): string
	local parts = {}
	for _, effect in unit.Effects do
		if effect.Kind == "Taunt" then
			table.insert(parts, `Taunt {effect.Turns}`)
		elseif effect.Kind == "Shield" then
			table.insert(parts, `Shield {effect.Amount}`)
		elseif effect.Kind == "Burn" then
			table.insert(parts, `Burn {effect.Turns}`)
		elseif effect.Kind == "Stun" then
			table.insert(parts, "Stunned")
		elseif effect.Stat then
			local arrow = if effect.Amount >= 0 then "+" else "-"
			table.insert(parts, `{effect.Stat}{arrow} {effect.Turns}`)
		end
	end
	return table.concat(parts, "  ")
end

-- Billboard above one unit: name, HP bar, own speed roll, effects, planned move.
local function unitLabel(side: number, slot: number, model: Model)
	local hpFraction = function()
		local unit = State.unit(side, slot)
		local hp = State.hp()[side] and State.hp()[side][slot]
		if not unit or not hp then
			return 0
		end
		return math.clamp(hp / unit.MaxHP, 0, 1)
	end
	return create("BillboardGui")({
		Name = `Label_{side}_{slot}`,
		Adornee = head(model),
		Size = UDim2.fromOffset(170, 74),
		StudsOffset = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		create("TextLabel")({
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Theme.Text,
			TextStrokeTransparency = 0.4,
			Text = function()
				local unit = State.unit(side, slot)
				return unit and unit.Name or ""
			end,
		}),
		create("Frame")({
			Position = UDim2.fromOffset(10, 20),
			Size = UDim2.new(1, -20, 0, 10),
			BackgroundColor3 = Color3.fromRGB(30, 30, 40),
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("Frame")({
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Side[side],
				Size = function()
					return UDim2.fromScale(hpFraction(), 1)
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			}),
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = Theme.Text,
			TextStrokeTransparency = 0.5,
			Text = function()
				local unit = State.unit(side, slot)
				local hp = State.hp()[side] and State.hp()[side][slot]
				if not unit or not hp then
					return ""
				end
				local text = `{hp}/{unit.MaxHP}`
				if unit.Speed and State.phase() == "Choosing" then
					text ..= `   SPD {unit.Speed}`
				end
				return text
			end,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(0, 47),
			Size = UDim2.new(1, 0, 0, 13),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Theme.Accent,
			TextStrokeTransparency = 0.5,
			Text = function()
				local unit = State.unit(side, slot)
				return if unit and unit.Alive then effectSummary(unit) else ""
			end,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(0, 60),
			Size = UDim2.new(1, 0, 0, 13),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = Theme.Good,
			TextStrokeTransparency = 0.5,
			Text = function()
				if side ~= State.side() or State.phase() ~= "Choosing" then
					return ""
				end
				local action = State.actions()[slot]
				local unit = State.unit(side, slot)
				if not action or not unit then
					return ""
				end
				local skill = unit.Skills[action.Skill]
				local text = skill and skill.Name or "?"
				if action.Target and skill and (skill.Target == "Enemy" or skill.Target == "Ally") then
					local targetSide = if skill.Target == "Enemy" then 3 - side else side
					local target = State.unit(targetSide, action.Target)
					text ..= ` -> {target and target.Name or action.Target}`
				end
				return text
			end,
		}),
	})
end

local function clearHighlights()
	for _, highlight in highlights do
		highlight:Destroy()
	end
	table.clear(highlights)
end

local function addHighlight(model: Model, color: Color3, fill: number)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = fill
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	table.insert(highlights, highlight)
end

-- Selected unit = white outline; valid targets while targeting = gold.
local function refreshHighlights()
	clearHighlights()
	local targeting = State.targeting()
	if targeting then
		local targetSide = if targeting.Kind == "Enemy" then 3 - State.side() else State.side()
		for slot = 1, 3 do
			local unit = State.unit(targetSide, slot)
			local model = ArenaView.model(targetSide, slot)
			if unit and unit.Alive and model then
				addHighlight(model, Theme.Accent, 0.6)
			end
		end
	end
	local selected = State.selected()
	if selected then
		local model = ArenaView.model(selected.Side, selected.Slot)
		if model then
			addHighlight(model, Color3.new(1, 1, 1), 0.85)
		end
	end
end

local function unitAt(position: Vector2): (number?, number?)
	-- Input positions exclude the top bar inset; ScreenPointToRay accounts for it.
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Arenas") }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	local current = hit and hit.Instance
	while current and current ~= workspace do
		if
			current:IsA("Model")
			and current:GetAttribute("Slot")
			and current:GetAttribute("BattleId") == State.battleId()
		then
			return current:GetAttribute("Side"), current:GetAttribute("Slot")
		end
		current = current.Parent
	end
	return nil, nil
end

-- Floating text above a unit, e.g. damage numbers.
function ArenaView.float(side: number, slot: number, text: string, color: Color3, big: boolean?)
	local model = ArenaView.model(side, slot)
	local anchor = model and head(model)
	if not anchor then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if big then 30 else 22
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = gui.StudsOffset + Vector3.new(0, 3, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.2, function()
		gui:Destroy()
	end)
end

-- Short step toward the target and back (client-side only).
function ArenaView.lunge(side: number, slot: number, targetSide: number?, targetSlot: number?)
	local model = ArenaView.model(side, slot)
	if not model then
		return
	end
	local origin = model:GetPivot()
	local target = if targetSide and targetSlot then ArenaView.model(targetSide, targetSlot) else nil
	local direction = if target then (target:GetPivot().Position - origin.Position).Unit else origin.LookVector
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(alpha)
		model:PivotTo(origin + direction * 3 * alpha)
	end)
	local out =
		TweenService:Create(value, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	out:Play()
	out.Completed:Wait()
	local back =
		TweenService:Create(value, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	back:Play()
	back.Completed:Wait()
	model:PivotTo(origin)
	value:Destroy()
end

function ArenaView.flash(side: number, slot: number, color: Color3)
	local model = ArenaView.model(side, slot)
	if not model then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.Adornee = model
	highlight.Parent = model
	TweenService:Create(highlight, TweenInfo.new(0.35), { FillTransparency = 1 }):Play()
	task.delay(0.4, function()
		highlight:Destroy()
	end)
end

function ArenaView.knockOut(side: number, slot: number)
	local model = ArenaView.model(side, slot)
	if not model then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			TweenService:Create(descendant, TweenInfo.new(0.5), { LocalTransparencyModifier = 0.75 }):Play()
		end
	end
end

function ArenaView.revive(side: number, slot: number)
	local model = ArenaView.model(side, slot)
	if not model then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			TweenService:Create(descendant, TweenInfo.new(0.4), { LocalTransparencyModifier = 0 }):Play()
		end
	end
end

function ArenaView.Mount(clickHandler: (number, number) -> ())
	onUnitClicked = clickHandler
	setCamera()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Persistent arenas stream in right away, but give them a moment.
	for side = 1, 2 do
		for slot = 1, 3 do
			local deadline = os.clock() + 5
			while not ArenaView.model(side, slot) and os.clock() < deadline do
				task.wait(0.1)
			end
		end
	end
	destroyRoot = vide.root(function(destroy)
		-- Billboards are parented straight to PlayerGui, the standard place for adorned GUIs.
		local labels = {}
		for side = 1, 2 do
			for slot = 1, 3 do
				local model = ArenaView.model(side, slot)
				if model then
					local label = unitLabel(side, slot, model)
					label.ResetOnSpawn = false
					label.Parent = playerGui
					table.insert(labels, label)
				end
			end
		end
		vide.effect(function()
			State.targeting()
			State.selected()
			State.snapshot()
			refreshHighlights()
		end)
		vide.cleanup(function()
			for _, label in labels do
				label:Destroy()
			end
			clearHighlights()
		end)
		return destroy
	end)
	inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local side, slot = unitAt(Vector2.new(input.Position.X, input.Position.Y))
		if side and slot and onUnitClicked then
			onUnitClicked(side, slot)
		end
	end)
end

function ArenaView.Unmount()
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	if destroyRoot then
		destroyRoot()
		destroyRoot = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

return ArenaView

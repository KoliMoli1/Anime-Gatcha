--!nonstrict
-- Builds the hub (roadmap Phase 4): a city plaza, one glowing circle per mode,
-- a raised display for the banner unit and a skyline around it. Everything is
-- generated here so the repo stays the source of truth; Phase A replaces the look.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubZones = require(Shared.Content.HubZones)
local Characters = require(Shared.Content.Characters)
local Theme = require(Shared.Theme)

local HubService = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
-- The plaza disc is 1 stud thick, centred on the origin: everything on it starts here.
local FLOOR = Vector3.new(0, 0.5, 0)

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	return p
end

-- Flat disc lying on the ground (cylinders point along X, so roll them onto their side).
local function disc(name: string, radius: number, height: number, position: Vector3, props): Part
	local p = part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
	})
	for key, value in props or {} do
		p[key] = value
	end
	return p
end

local function label(parent: Instance, title: string, subtitle: string, color: Color3, offset: Vector3, scale: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(14 * scale, 4.2 * scale)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Parent = parent
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(1, 0.62)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = Color3.fromRGB(10, 12, 20)
	titleLabel.Text = title
	titleLabel.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.64)
	sub.Size = UDim2.fromScale(1, 0.32)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Theme.Text
	sub.TextStrokeTransparency = 0.2
	sub.Text = subtitle
	sub.Parent = gui
	return gui
end

local function buildZone(zone, parent: Instance)
	local center = HubZones.ORIGIN + zone.Offset + FLOOR
	local model = Instance.new("Model")
	model.Name = zone.Id
	model:SetAttribute("Zone", zone.Id)

	local dark = zone.Color:Lerp(Color3.fromRGB(15, 18, 28), 0.72)
	disc("Base", zone.Radius + 1.6, 0.5, center + Vector3.new(0, 0.25, 0), {
		Color = Color3.fromRGB(28, 32, 44),
		Material = Enum.Material.Slate,
	}).Parent =
		model
	disc("Ring", zone.Radius + 0.6, 0.6, center + Vector3.new(0, 0.32, 0), {
		Color = zone.Color,
		Material = Enum.Material.Neon,
	}).Parent =
		model
	local pad = disc("Pad", zone.Radius - 0.4, 0.7, center + Vector3.new(0, 0.36, 0), {
		Color = dark,
		Material = Enum.Material.Glass,
		Reflectance = 0.15,
	})
	pad.Parent = model
	disc("Core", zone.Radius * 0.35, 0.74, center + Vector3.new(0, 0.38, 0), {
		Color = zone.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	}).Parent =
		model

	-- Soft light column and rising sparkles so the circle reads from across the plaza.
	local beamHolder = part({
		Name = "Glow",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 1, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	beamHolder.Parent = model
	local light = Instance.new("PointLight")
	light.Color = zone.Color
	light.Range = zone.Radius * 2.2
	light.Brightness = 2.5
	light.Parent = beamHolder

	local emitterPart = disc("Sparkles", zone.Radius - 1, 0.2, center + Vector3.new(0, 0.6, 0), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	emitterPart.Parent = model
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = SPARKLES
	sparkles.Color = ColorSequence.new(zone.Color, Color3.new(1, 1, 1))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.2)
	sparkles.Lifetime = NumberRange.new(1.6, 2.6)
	sparkles.Speed = NumberRange.new(3, 6)
	sparkles.EmissionDirection = Enum.NormalId.Right
	sparkles.Rate = 14
	sparkles.Shape = Enum.ParticleEmitterShape.Cylinder
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkles.Parent = emitterPart

	label(pad, zone.Label, zone.Subtitle, zone.Color, Vector3.new(0, 9, 0), 1)
	model.PrimaryPart = pad
	model.Parent = parent
	return model
end

-- Raised display behind the Summon circle: a stepped pedestal and the banner unit, large.
local function buildBannerDisplay(parent: Instance)
	local center = HubZones.ORIGIN + HubZones.BANNER_OFFSET + FLOOR
	local model = Instance.new("Model")
	model.Name = "BannerDisplay"
	local accent = Theme.Accent
	disc("Step1", 16, 2, center + Vector3.new(0, 1, 0), {
		Color = Color3.fromRGB(30, 34, 48),
		Material = Enum.Material.Slate,
	}).Parent =
		model
	disc("Step2", 12, 2, center + Vector3.new(0, 3, 0), {
		Color = Color3.fromRGB(38, 43, 60),
		Material = Enum.Material.Slate,
	}).Parent =
		model
	disc("Trim", 12.4, 0.4, center + Vector3.new(0, 4.1, 0), {
		Color = accent,
		Material = Enum.Material.Neon,
	}).Parent =
		model
	local top = disc("Top", 11.6, 0.6, center + Vector3.new(0, 4.3, 0), {
		Color = Color3.fromRGB(22, 26, 38),
		Material = Enum.Material.Glass,
		Reflectance = 0.2,
	})
	top.Parent = model

	local def = Characters[HubZones.FEATURED_UNIT]
	local rigs = ReplicatedStorage:FindFirstChild("UnitRigs")
	local template = def and rigs and rigs:FindFirstChild(def.Class)
	if template then
		local rig = template:Clone()
		rig.Name = "FeaturedUnit"
		rig:ScaleTo(rig:GetScale() * 3)
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		local root = rig:FindFirstChild("HumanoidRootPart")
		local lift = if humanoid and root then humanoid.HipHeight + root.Size.Y / 2 else 4
		-- Face the spawn (+Z).
		local base = center + Vector3.new(0, 4.6 + lift, 0)
		rig:PivotTo(CFrame.lookAt(base, base + Vector3.new(0, 0, 1)))
		rig.Parent = model
	end

	local aura = disc("Aura", 9, 0.2, center + Vector3.new(0, 4.8, 0), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	aura.Parent = model
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = SPARKLES
	glow.Color = ColorSequence.new(accent)
	glow.LightEmission = 1
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	glow.Lifetime = NumberRange.new(2, 3.5)
	glow.Speed = NumberRange.new(4, 9)
	glow.EmissionDirection = Enum.NormalId.Right
	glow.Rate = 24
	glow.Shape = Enum.ParticleEmitterShape.Cylinder
	glow.Parent = aura
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Right
	light.Color = accent
	light.Brightness = 4
	light.Range = 30
	light.Angle = 70
	light.Parent = aura

	local title = def and `{def.Name}  {string.rep("★", def.Rarity)}` or "Featured"
	label(top, "FEATURED", title, accent, Vector3.new(0, 26, 0), 1.3)
	model.Parent = parent
end

-- Plain towers with lit window bands around the plaza (modern city setting).
local function buildSkyline(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Skyline"
	local rng = Random.new(20261107)
	local palette = {
		Color3.fromRGB(34, 38, 54),
		Color3.fromRGB(44, 48, 66),
		Color3.fromRGB(28, 31, 44),
	}
	local windowColors = { Theme.Accent, Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 120, 180) }
	local count = 34
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local distance = rng:NextNumber(150, 210)
		local width = rng:NextNumber(22, 38)
		local depth = rng:NextNumber(22, 38)
		local height = rng:NextNumber(60, 190)
		local position = HubZones.ORIGIN
			+ Vector3.new(math.cos(angle) * distance, height / 2, math.sin(angle) * distance)
		local facing = CFrame.lookAt(position, Vector3.new(HubZones.ORIGIN.X, position.Y, HubZones.ORIGIN.Z))
		local tower = part({
			Name = "Tower",
			Size = Vector3.new(width, height, depth),
			CFrame = facing,
			Color = palette[rng:NextInteger(1, #palette)],
			Material = Enum.Material.Concrete,
			CastShadow = false,
		})
		tower.Parent = folder
		local windowColor = windowColors[rng:NextInteger(1, #windowColors)]
		local bands = math.floor(height / 14)
		for b = 1, bands do
			if rng:NextNumber() < 0.7 then
				local y = -height / 2 + b * 14 - 4
				part({
					Name = "Windows",
					Size = Vector3.new(width * 0.86, 1.4, 0.4),
					CFrame = facing * CFrame.new(0, y, -depth / 2 - 0.15),
					Color = windowColor,
					Material = Enum.Material.Neon,
					Transparency = rng:NextNumber(0.1, 0.5),
					CanCollide = false,
					CanQuery = false,
					CastShadow = false,
				}).Parent =
					folder
			end
		end
	end
	folder.Parent = parent
end

local function buildPlaza(parent: Instance)
	local origin = HubZones.ORIGIN
	disc("Plaza", HubZones.PLAZA_RADIUS, 1, origin + Vector3.new(0, 0, 0), {
		Color = Color3.fromRGB(78, 84, 104),
		Material = Enum.Material.Pavement,
	}).Parent =
		parent
	disc("PlazaTrim", HubZones.PLAZA_RADIUS + 1.5, 0.8, origin + Vector3.new(0, -0.05, 0), {
		Color = Color3.fromRGB(90, 160, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	}).Parent =
		parent
	-- Walkway from the spawn to the Summon circle.
	part({
		Name = "Walkway",
		Size = Vector3.new(10, 0.3, 74),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.55, 8)),
		Color = Color3.fromRGB(70, 75, 92),
		Material = Enum.Material.Slate,
	}).Parent =
		parent
	disc("Street", 260, 0.6, origin + Vector3.new(0, -0.4, 0), {
		Color = Color3.fromRGB(30, 32, 40),
		Material = Enum.Material.Asphalt,
	}).Parent =
		parent
end

local function setupSpawn()
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Parent = workspace
	end
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	local position = HubZones.ORIGIN + HubZones.SPAWN_OFFSET + Vector3.new(0, 0.6, 0)
	spawn.CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

local function setupLighting()
	Lighting.ClockTime = 18.3
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(110, 105, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 130, 170)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	if not Lighting:FindFirstChild("HubBloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "HubBloom"
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.4
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChild("HubColor") then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "HubColor"
		grade.Saturation = 0.12
		grade.Contrast = 0.08
		grade.Parent = Lighting
	end
end

-- Rebuilds Workspace.Hub. Safe to call again (e.g. from the command bar while tuning).
function HubService.Build()
	local old = workspace:FindFirstChild("Hub")
	if old then
		old:Destroy()
	end
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	buildPlaza(hub)
	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = hub
	for _, zone in HubZones.List do
		buildZone(zone, zones)
	end
	buildBannerDisplay(hub)
	buildSkyline(hub)
	hub.Parent = workspace
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate.Transparency = 1
		baseplate.CanCollide = true
	end
	setupSpawn()
	setupLighting()
	return hub
end

function HubService.Start()
	HubService.Build()
end

return HubService

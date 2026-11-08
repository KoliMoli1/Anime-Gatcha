--!nonstrict
-- Each player's active team follows them around the hub (roadmap Phase 4: social status).
-- Drawn locally on every client from the player's "TeamIds" attribute, so it costs the
-- server nothing. Hidden while the player is in a battle. Placeholder rigs until Phase A.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Characters = require(ReplicatedStorage.Shared.Content.Characters)
local Theme = require(ReplicatedStorage.Shared.Theme)

local TeamFollowers = {}

TeamFollowers.SCALE = 0.55
-- Formation behind the player (player-local: +X right, +Z behind).
TeamFollowers.OFFSETS = { Vector3.new(-3.6, 0, 3.4), Vector3.new(0, 0, 5.2), Vector3.new(3.6, 0, 3.4) }
TeamFollowers.FOLLOW_SPEED = 8
TeamFollowers.MAX_DISTANCE = 400

type Follower = { Model: Model, Lift: number, Position: Vector3, Facing: Vector3, Phase: number }
type Entry = { Key: string, Followers: { Follower } }

local entries: { [Player]: Entry } = {}
local folder = Instance.new("Folder")
folder.Name = "TeamFollowers"

local function clear(player: Player)
	local entry = entries[player]
	if entry then
		for _, follower in entry.Followers do
			follower.Model:Destroy()
		end
		entries[player] = nil
	end
end

local function makeFollower(id: string): Follower?
	local def = Characters[id]
	local rigs = ReplicatedStorage:FindFirstChild("UnitRigs")
	local template = def and rigs and rigs:FindFirstChild(def.Class)
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = id
	model:ScaleTo(TeamFollowers.SCALE)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local lift = if humanoid and root then humanoid.HipHeight + root.Size.Y / 2 else 1.5
	-- Small class-coloured ring under each follower.
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 2.6, 2.6)
	ring.Material = Enum.Material.Neon
	ring.Color = Theme.Class[def.Class] or Color3.new(1, 1, 1)
	ring.Transparency = 0.45
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = model
	model.Parent = folder
	return {
		Model = model,
		Lift = lift,
		Position = Vector3.zero,
		Facing = Vector3.new(0, 0, -1),
		Phase = math.random() * 6,
	}
end

local function rebuild(player: Player, key: string)
	clear(player)
	local followers = {}
	for _, id in string.split(key, ",") do
		local follower = makeFollower(id)
		if follower then
			table.insert(followers, follower)
		end
	end
	entries[player] = { Key = key, Followers = followers }
end

-- Feet position under the player's character, or nil if it isn't standing in the world.
local function anchorOf(player: Player): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local floorY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local base = Vector3.new(root.Position.X, floorY, root.Position.Z)
	return CFrame.lookAt(base, base + flat.Unit)
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local key = player:GetAttribute("TeamIds")
		local anchor = anchorOf(player)
		local visible = type(key) == "string"
			and key ~= ""
			and anchor ~= nil
			and not player:GetAttribute("InBattle")
			and (not camera or (anchor.Position - camera.CFrame.Position).Magnitude < TeamFollowers.MAX_DISTANCE)
		if not visible then
			clear(player)
			continue
		end
		local entry = entries[player]
		local fresh = false
		if not entry or entry.Key ~= key then
			rebuild(player, key)
			entry = entries[player]
			fresh = true
		end
		local alpha = 1 - math.exp(-TeamFollowers.FOLLOW_SPEED * dt)
		for index, follower in entry.Followers do
			local target = (anchor * CFrame.new(TeamFollowers.OFFSETS[index] or Vector3.zero)).Position
			local previous = follower.Position
			follower.Position = if fresh then target else previous:Lerp(target, alpha)
			local moved = follower.Position - previous
			local flat = Vector3.new(moved.X, 0, moved.Z)
			if flat.Magnitude > 0.02 then
				follower.Facing = follower.Facing:Lerp(flat.Unit, math.min(1, alpha * 2))
			elseif (follower.Position - target).Magnitude < 0.3 then
				follower.Facing = follower.Facing:Lerp(anchor.LookVector, alpha)
			end
			local bob = math.sin(now * 3 + follower.Phase) * 0.12
			local feet = follower.Position
			local pivot = feet + Vector3.new(0, follower.Lift + bob, 0)
			local facing = if follower.Facing.Magnitude > 0.01 then follower.Facing.Unit else anchor.LookVector
			follower.Model:PivotTo(CFrame.lookAt(pivot, pivot + facing))
			local ring = follower.Model:FindFirstChild("Ring")
			if ring then
				ring.CFrame = CFrame.new(feet + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
	end
end

function TeamFollowers.Start()
	folder.Parent = workspace
	Players.PlayerRemoving:Connect(clear)
	RunService.RenderStepped:Connect(step)
end

return TeamFollowers

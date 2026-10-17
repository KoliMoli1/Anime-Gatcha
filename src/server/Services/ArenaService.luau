--!nonstrict
-- Builds a battle arena: a floor, six pads and a placeholder rig per unit.
-- Arenas float high above the hub, one slot per active battle. Phase 6 moves
-- PvP battles to reserved servers; Phase A replaces the placeholder look.
--
-- Layout (arena-local, side 1 at +Z facing -Z, side 2 at -Z facing +Z):
--   units at x = -8, 0, 8 and z = +/-10; each player stands behind their team at z = +/-21.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)

local ArenaService = {}

local ORIGIN = Vector3.new(0, 400, 0)
local SPACING = 260
local UNIT_SCALE = 0.8
local SLOT_X = { -8, 0, 8 }
local UNIT_Z = 10
local STAND_Z = 21

local folder = workspace:FindFirstChild("Arenas")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Arenas"
	folder.Parent = workspace
end

local used: { [number]: boolean } = {}

local function freeSlot(): number
	local index = 0
	while used[index] do
		index += 1
	end
	used[index] = true
	return index
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	return p
end

-- Direction a side's units face (toward the enemy).
local function facing(side: number): number
	return if side == 1 then -1 else 1
end

function ArenaService.UnitCFrame(center: CFrame, side: number, slot: number): CFrame
	local z = UNIT_Z * -facing(side)
	local position = center * CFrame.new(SLOT_X[slot], 0, z)
	return CFrame.lookAt(position.Position, (position * CFrame.new(0, 0, facing(side))).Position)
end

function ArenaService.StandCFrame(center: CFrame, side: number): CFrame
	local z = STAND_Z * -facing(side)
	local position = center * CFrame.new(0, 3, z)
	return CFrame.lookAt(position.Position, (position * CFrame.new(0, 0, facing(side))).Position)
end

local function placeholderRig(color: Color3): Model
	local ok, rig = pcall(function()
		local description = Instance.new("HumanoidDescription")
		for _, field in { "HeadColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor", "TorsoColor" } do
			description[field] = color
		end
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and rig then
		rig:ScaleTo(UNIT_SCALE)
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		local root = rig:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true
		end
		return rig
	end
	-- Fallback: a simple block figure if rig creation is unavailable.
	local model = Instance.new("Model")
	local body = part({ Name = "HumanoidRootPart", Size = Vector3.new(2, 3, 1.2), Color = color, Parent = model })
	part({
		Name = "Head",
		Size = Vector3.new(1.4, 1.4, 1.4),
		Color = color,
		CFrame = body.CFrame * CFrame.new(0, 2.2, 0),
		Parent = model,
	})
	model.PrimaryPart = body
	return model
end

-- Height from a rig's pivot to its feet, so it stands on the pad.
local function footOffset(rig: Model): number
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	if humanoid and root then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 1.5
end

export type Arena = {
	Id: string,
	Slot: number,
	Center: CFrame,
	Model: Model,
	Units: { [number]: { [number]: Model } },
}

-- teams[side][slot] = { Name, Class }
function ArenaService.Create(battleId: string, teams): Arena
	local slot = freeSlot()
	local center = CFrame.new(ORIGIN + Vector3.new(slot * SPACING, 0, 0))
	local model = Instance.new("Model")
	model.Name = `Arena_{battleId}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("BattleId", battleId)

	part({
		Name = "Floor",
		Size = Vector3.new(64, 2, 64),
		CFrame = center * CFrame.new(0, -1, 0),
		Color = Color3.fromRGB(46, 52, 70),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- Low walls so nobody walks off the edge.
	for _, offset in { Vector3.new(0, 2, 32), Vector3.new(0, 2, -32), Vector3.new(32, 2, 0), Vector3.new(-32, 2, 0) } do
		local alongX = offset.X == 0
		part({
			Name = "Wall",
			Size = if alongX then Vector3.new(64, 6, 1) else Vector3.new(1, 6, 64),
			CFrame = center * CFrame.new(offset),
			Transparency = 1,
			Parent = model,
		})
	end

	local unitsFolder = Instance.new("Folder")
	unitsFolder.Name = "Units"
	unitsFolder.Parent = model
	local units = { {}, {} }
	for side = 1, 2 do
		for index = 1, 3 do
			local unitCFrame = ArenaService.UnitCFrame(center, side, index)
			part({
				Name = `Pad_{side}_{index}`,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 6, 6),
				CFrame = CFrame.new(unitCFrame.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Theme.Side[side],
				Material = Enum.Material.Neon,
				Transparency = 0.35,
				CanCollide = false,
				Parent = model,
			})
			local info = teams[side][index]
			local rig = placeholderRig(Theme.Class[info.Class] or Color3.new(0.8, 0.8, 0.8))
			rig.Name = `{side}_{index}`
			rig:SetAttribute("BattleId", battleId)
			rig:SetAttribute("Side", side)
			rig:SetAttribute("Slot", index)
			rig:SetAttribute("UnitName", info.Name)
			rig:PivotTo(unitCFrame + Vector3.new(0, 0.4 + footOffset(rig), 0))
			rig.Parent = unitsFolder
			units[side][index] = rig
		end
	end

	model.Parent = folder
	return { Id = battleId, Slot = slot, Center = center, Model = model, Units = units }
end

function ArenaService.Destroy(arena: Arena)
	used[arena.Slot] = nil
	arena.Model:Destroy()
end

return ArenaService

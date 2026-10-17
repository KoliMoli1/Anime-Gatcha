--!strict
-- Placeholder colors shared by the arena (server) and the battle screen (client).
-- Phase A (art) replaces these with the real art direction.

local Theme = {}

Theme.Class = {
	Attack = Color3.fromRGB(225, 80, 80),
	Defense = Color3.fromRGB(95, 130, 210),
	Support = Color3.fromRGB(85, 195, 125),
	Disrupt = Color3.fromRGB(165, 95, 215),
	Speed = Color3.fromRGB(240, 200, 70),
} :: { [string]: Color3 }

Theme.Side = {
	[1] = Color3.fromRGB(70, 150, 255),
	[2] = Color3.fromRGB(240, 90, 90),
} :: { [number]: Color3 }

Theme.Stat = {
	HP = Color3.fromRGB(110, 210, 120),
	ATK = Color3.fromRGB(235, 90, 80),
	DEF = Color3.fromRGB(100, 140, 230),
	SPD = Color3.fromRGB(245, 205, 70),
	CritRate = Color3.fromRGB(245, 140, 60),
	CritDamage = Color3.fromRGB(200, 90, 160),
	EFF = Color3.fromRGB(160, 100, 230),
	RES = Color3.fromRGB(90, 200, 210),
} :: { [string]: Color3 }

Theme.Panel = Color3.fromRGB(22, 26, 38)
Theme.PanelLight = Color3.fromRGB(38, 45, 64)
Theme.Text = Color3.fromRGB(235, 240, 250)
Theme.TextDim = Color3.fromRGB(160, 170, 190)
Theme.Good = Color3.fromRGB(110, 220, 140)
Theme.Bad = Color3.fromRGB(240, 100, 100)
Theme.Accent = Color3.fromRGB(255, 205, 80)

return Theme

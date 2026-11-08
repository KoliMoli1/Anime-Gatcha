--!strict
-- Hub mode circles (roadmap Phase 4). Stand inside a circle to open that mode;
-- step out to close it (PvP: joins the queue on enter, leaves it on exit).
-- Positions are hub-local: the plaza is centred on HubZones.ORIGIN, the spawn faces -Z.

export type Zone = {
	Id: string,
	Label: string,
	Subtitle: string,
	Color: Color3,
	Offset: Vector3,
	Radius: number,
}

local HubZones = {}

HubZones.ORIGIN = Vector3.new(0, 0, 0)
HubZones.PLAZA_RADIUS = 96
HubZones.SPAWN_OFFSET = Vector3.new(0, 0, 46)
-- How far above the plaza floor a player can be and still count as standing in a circle.
HubZones.MAX_HEIGHT = 8
-- The banner unit on the raised display. Phase 5 reads this from the live banner.
HubZones.FEATURED_UNIT = "Boku"
HubZones.BANNER_OFFSET = Vector3.new(0, 0, -70)

HubZones.List = {
	{
		Id = "Summon",
		Label = "SUMMON",
		Subtitle = "Pull new characters",
		Color = Color3.fromRGB(255, 205, 80),
		Offset = Vector3.new(0, 0, -40),
		Radius = 11,
	},
	{
		Id = "PvP",
		Label = "PVP",
		Subtitle = "Stand here to queue",
		Color = Color3.fromRGB(240, 85, 85),
		Offset = Vector3.new(-40, 0, -22),
		Radius = 10,
	},
	{
		Id = "Story",
		Label = "STORY",
		Subtitle = "Fight through the city",
		Color = Color3.fromRGB(80, 150, 255),
		Offset = Vector3.new(40, 0, -22),
		Radius = 10,
	},
	{
		Id = "Events",
		Label = "EVENTS",
		Subtitle = "Limited-time fights",
		Color = Color3.fromRGB(90, 220, 140),
		Offset = Vector3.new(-58, 0, 12),
		Radius = 9,
	},
	{
		Id = "Shop",
		Label = "SHOP",
		Subtitle = "Gems, cosmetics, shards",
		Color = Color3.fromRGB(200, 110, 255),
		Offset = Vector3.new(58, 0, 12),
		Radius = 9,
	},
} :: { Zone }

HubZones.ById = {} :: { [string]: Zone }
for _, zone in HubZones.List do
	HubZones.ById[zone.Id] = zone
end

-- The zone whose circle contains this world position, or nil.
function HubZones.at(position: Vector3): Zone?
	local relative = position - HubZones.ORIGIN
	if relative.Y < -2 or relative.Y > HubZones.MAX_HEIGHT then
		return nil
	end
	for _, zone in HubZones.List do
		local dx = relative.X - zone.Offset.X
		local dz = relative.Z - zone.Offset.Z
		if dx * dx + dz * dz <= zone.Radius * zone.Radius then
			return zone
		end
	end
	return nil
end

return HubZones

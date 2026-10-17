--!strict
-- Interim roll rules carried over from the prototype so the existing summon button
-- keeps working. Phase 5 replaces this with banners, odds display and pity.

local GachaRules = {}

GachaRules.RollCost = 10
GachaRules.RollCooldown = 0.75
GachaRules.CharacterRanges = {
	{ Min = 950, Max = 1000, CharacterId = "TrainingAttack" },
	{ Min = 900, Max = 949, CharacterId = "TrainingDefense" },
	{ Min = 800, Max = 899, CharacterId = "TrainingSpeed" },
	{ Min = 700, Max = 799, CharacterId = "TrainingDisrupt" },
	{ Min = 1, Max = 699, CharacterId = "TrainingSupport" },
}

function GachaRules.characterForRoll(value: number): string?
	if type(value) ~= "number" or value % 1 ~= 0 then
		return nil
	end
	for _, range in GachaRules.CharacterRanges do
		if value >= range.Min and value <= range.Max then
			return range.CharacterId
		end
	end
	return nil
end

return GachaRules

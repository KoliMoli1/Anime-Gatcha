--!strict
-- Character roster. Training units are the free starter team; their ids are kept
-- from the prototype so existing saves still own them.

local Types = require("../Types")
local Classes = require("./Classes")

local Characters: { [string]: Types.CharacterDef } = {}

local function define(
	id: string,
	name: string,
	class: Types.ClassName,
	rarity: number,
	extra: {
		Skills: { string },
		Passive: string?,
		Starter: boolean?,
		Stats: { [string]: number }?,
	}
)
	local stats = Classes.statsFor(class, rarity)
	if extra.Stats then
		for stat, value in extra.Stats do
			(stats :: any)[stat] = value
		end
	end
	Characters[id] = {
		Id = id,
		Name = name,
		Rarity = rarity,
		Class = class,
		Stats = stats,
		Speed = Classes.speedFor(class, rarity),
		EnergyRegen = Classes.Templates[class].EnergyRegen,
		Skills = extra.Skills,
		Passive = extra.Passive,
		Starter = extra.Starter,
	}
end

define("TrainingAttack", "Training Attack", "Attack", 5, {
	Skills = { "atk_basic", "atk_skill", "atk_ult" },
	Starter = true,
})
define("TrainingDefense", "Training Defense", "Defense", 5, {
	Skills = { "def_basic", "def_skill", "def_ult" },
	Passive = "thorned_guard",
	Starter = true,
})
define("TrainingSupport", "Training Support", "Support", 4, {
	Skills = { "sup_basic", "sup_skill", "sup_ult" },
	Starter = true,
})
define("TrainingDisrupt", "Training Disrupt", "Disrupt", 4, {
	Skills = { "dis_basic", "dis_skill", "dis_ult" },
	Starter = true,
})
define("TrainingSpeed", "Training Speed", "Speed", 4, {
	Skills = { "spd_basic", "spd_skill", "spd_ult" },
	Passive = "riposte",
	Starter = true,
})

return Characters

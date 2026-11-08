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
		Kit: string?,
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
		Kit = extra.Kit,
	}
end

define("TrainingAttack", "Training Attack", "Attack", 4, {
	Skills = { "atk_basic", "atk_skill", "atk_ult" },
	Starter = true,
})
define("TrainingDefense", "Training Defense", "Defense", 4, {
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

-- Launch 5-stars. Display names are placeholders until the team renames them.
define("Boku", "Boku", "Attack", 5, {
	Skills = { "boku_s1", "boku_s2", "boku_s3" },
	Passive = "boku_power_meter",
	Kit = "Boku",
})
define("Kojo", "Kojo", "Defense", 5, {
	Skills = { "kojo_s1", "kojo_s2", "kojo_s3" },
	Passive = "kojo_barrier",
	Kit = "Kojo",
})
define("Sasta", "Sasta", "Defense", 5, {
	Skills = { "sasta_a1", "sasta_a2", "sasta_a3" },
	Passive = "sasta_seal",
	Kit = "Sasta",
})
define("Shade", "Shade", "Speed", 5, {
	Skills = { "shade_s1", "shade_s2", "shade_s3" },
	Passive = "shade_shadow_step",
	Kit = "Shade",
})

return Characters

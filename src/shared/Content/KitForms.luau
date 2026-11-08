--!strict
-- Extra skills a launch kit brings into play mid-battle (form swaps, auto-triggers,
-- summons). Combat/Kits swaps them in; the Characters screen lists them.

export type Form = { Label: string, Skills: { string } }

local KitForms: { [string]: Form } = {
	Boku = { Label = "Transformed", Skills = { "boku_t1", "boku_t2", "boku_t3" } },
	Kojo = { Label = "Auto-triggered", Skills = { "kojo_unique" } },
	Sasta = { Label = "Devil form", Skills = { "sasta_d1", "sasta_d2", "sasta_d3" } },
	Shade = { Label = "Raised shadow", Skills = { "shade_shadow_strike" } },
}

return KitForms

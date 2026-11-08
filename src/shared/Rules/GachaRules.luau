--!strict
-- Kept for older callers (the interim Summon panel reads RollCost). The real rules live in
-- Rules/Summon and Content/Banners.

local Summon = require("./Summon")

local GachaRules = {}

GachaRules.RollCost = Summon.COST

return GachaRules

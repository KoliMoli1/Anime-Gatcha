local GachaRules = {}

GachaRules.RollCost = 10
GachaRules.DuplicateReward = 2
GachaRules.RollCooldown = 0.75
GachaRules.CharacterRanges = {
    {Min = 950, Max = 1000, CharacterId = "TrainingAttack"},
    {Min = 900, Max = 949, CharacterId = "TrainingDefense"},
    {Min = 800, Max = 899, CharacterId = "TrainingSpeed"},
    {Min = 700, Max = 799, CharacterId = "TrainingDisrupt"},
    {Min = 1, Max = 699, CharacterId = "TrainingSupport"},
}

function GachaRules.CharacterForRoll(value)
    if type(value) ~= "number" or value % 1 ~= 0 then return nil end
    for _, range in ipairs(GachaRules.CharacterRanges) do
        if value >= range.Min and value <= range.Max then return range.CharacterId end
    end
    return nil
end

function GachaRules.DuplicateNetCost()
    return GachaRules.RollCost - GachaRules.DuplicateReward
end

assert(GachaRules.DuplicateReward >= 0 and GachaRules.DuplicateReward < GachaRules.RollCost, "Duplicate reward must not create roll-currency profit")

return GachaRules

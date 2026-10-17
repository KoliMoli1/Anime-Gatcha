local CombatMath = {}

function CombatMath.CalculateFinalStats(baseStats, modifiers)
    assert(type(baseStats) == "table", "baseStats must be a table")
    local final = table.clone(baseStats)
    for stat, modifier in pairs(modifiers or {}) do
        if final[stat] ~= nil and type(modifier) == "number" then
            final[stat] += modifier
        end
    end
    final.MaxHealth = math.max(1, final.MaxHealth or 1)
    final.Attack = math.max(1, final.Attack or 1)
    final.Defense = math.max(0, final.Defense or 0)
    final.Speed = math.max(1, final.Speed or 1)
    final.CritChance = math.clamp(final.CritChance or 0, 0, 1)
    final.CritDamage = math.max(1, final.CritDamage or 1)
    return final
end

-- Pure when options.CritRoll is provided, which keeps combat tests deterministic.
function CombatMath.CalculateDamage(attackerStats, defenderStats, skillPower, options)
    assert(type(attackerStats) == "table", "attackerStats must be a table")
    assert(type(defenderStats) == "table", "defenderStats must be a table")
    options = options or {}
    local attackMultiplier = math.max(0, options.AttackMultiplier or 1)
    local defenseMultiplier = math.max(0, options.DefenseMultiplier or 1)
    local critChance = math.clamp((attackerStats.CritChance or 0) + (options.CritBonus or 0), 0, 1)
    local roll = options.CritRoll
    if roll == nil then
        local random = options.Random
        roll = random and random:NextNumber() or Random.new():NextNumber()
    end
    local critical = roll < critChance
    local rawDamage = (attackerStats.Attack or 1) * attackMultiplier + (skillPower or 0)
    local mitigated = rawDamage - (defenderStats.Defense or 0) * defenseMultiplier
    local amount = math.max(1, mitigated)
    if critical then
        amount *= math.max(1, attackerStats.CritDamage or 1)
    end
    return {
        Amount = math.max(1, math.floor(amount + 0.5)),
        IsCritical = critical,
    }
end

return CombatMath

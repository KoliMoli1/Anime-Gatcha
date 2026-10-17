local CombatMath = require(script.Parent:WaitForChild("CombatMath"))

local BattleEngine = {}

BattleEngine.MAX_ENERGY = 300
BattleEngine.ACTION2_COST = { Attack = 100, Defense = 100, Support = 40, Disrupt = 70, Speed = 60 }
BattleEngine.ENERGY_GAIN = { Attack = 20, Defense = 10, Support = 40, Disrupt = 30, Speed = 25 }
BattleEngine.CLASS_POWER = { Attack = 280, Defense = 150, Support = 180, Disrupt = 170, Speed = 160 }

function BattleEngine.ClassOf(definition)
    for class in pairs(definition.Classes or {}) do return class end
    return "Unknown"
end

function BattleEngine.Action2Cost(definition)
    return BattleEngine.ACTION2_COST[BattleEngine.ClassOf(definition)] or 100
end

function BattleEngine.TeamEnergyGain(team, definitions)
    local total = 0
    for _, id in ipairs(team) do
        local definition = definitions[id]
        if definition then total += BattleEngine.ENERGY_GAIN[BattleEngine.ClassOf(definition)] or 0 end
    end
    return total
end

function BattleEngine.FirstLiving(health)
    for i = 1, #health do if (health[i] or 0) > 0 then return i end end
    return nil
end

function BattleEngine.ResolveTarget(requested, health, tauntSlot)
    if tauntSlot and (health[tauntSlot] or 0) > 0 then return tauntSlot end
    if requested and (health[requested] or 0) > 0 then return requested end
    return BattleEngine.FirstLiving(health)
end

function BattleEngine.ModifiedSpeed(definition, hasteTurns, disruptedTurns)
    local speed = math.max(1, definition.BaseStats.Speed or 1)
    if (hasteTurns or 0) > 0 then speed *= 1.5 end
    if (disruptedTurns or 0) > 0 then speed *= 0.65 end
    return math.max(1, math.floor(speed))
end

-- Highest effective speed acts first. Ties are deterministic: player before enemy, then slot order.
function BattleEngine.BuildActionQueue(playerTeam, enemyTeam, playerHealth, enemyHealth, playerActions, enemyActions, definitions, speedEffects)
    speedEffects = speedEffects or {}
    local queue = {}
    local function add(side, team, health, actions)
        local effects = speedEffects[side] or {}
        for slot, id in ipairs(team) do
            if (health[slot] or 0) > 0 then
                table.insert(queue, {
                    Side = side,
                    Slot = slot,
                    CharacterId = id,
                    Kind = actions[slot] or "Attack",
                    Speed = BattleEngine.ModifiedSpeed(definitions[id], (effects.Haste or {})[slot], effects.Disrupted),
                })
            end
        end
    end
    add("Player", playerTeam, playerHealth, playerActions)
    add("Enemy", enemyTeam, enemyHealth, enemyActions)
    table.sort(queue, function(a, b)
        if a.Speed ~= b.Speed then return a.Speed > b.Speed end
        if a.Side ~= b.Side then return a.Side == "Player" end
        return a.Slot < b.Slot
    end)
    return queue
end

function BattleEngine.CalculateAttack(attackerDefinition, defenderDefinition, options)
    options = options or {}
    local class = BattleEngine.ClassOf(attackerDefinition)
    return CombatMath.CalculateDamage(
        attackerDefinition.BaseStats,
        defenderDefinition.BaseStats,
        BattleEngine.CLASS_POWER[class] or 70,
        options
    )
end

function BattleEngine.Winner(playerHealth, enemyHealth)
    local playerAlive = BattleEngine.FirstLiving(playerHealth) ~= nil
    local enemyAlive = BattleEngine.FirstLiving(enemyHealth) ~= nil
    if playerAlive and not enemyAlive then return "Player" end
    if enemyAlive and not playerAlive then return "Enemy" end
    if not playerAlive and not enemyAlive then return "Draw" end
    return nil
end

return BattleEngine

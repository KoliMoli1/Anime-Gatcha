return function(t)
 local CombatMath=require(game.ReplicatedStorage.AnimeCombatCore.Shared.CombatMath)
 local expect=t.expect
 local attacker={MaxHealth=100,Attack=100,Defense=10,Speed=20,CritChance=.25,CritDamage=2}
 local defender={MaxHealth=100,Attack=10,Defense=30,Speed=10,CritChance=0,CritDamage=1}

 -- Non-critical damage subtracts defense after skill power.
 t.test('calculates deterministic non-critical damage',function()
  local result=CombatMath.CalculateDamage(attacker,defender,20,{CritRoll=.9})
  expect.equal(result.Amount,90);expect.falsy(result.IsCritical)
 end)

 -- Critical hits multiply mitigated damage by critical damage.
 t.test('calculates deterministic critical damage',function()
  local result=CombatMath.CalculateDamage(attacker,defender,20,{CritRoll=.1})
  expect.equal(result.Amount,180);expect.truthy(result.IsCritical)
 end)

 -- Damage always has a minimum of one.
 t.test('enforces minimum damage',function()
  local result=CombatMath.CalculateDamage({Attack=1,CritChance=0,CritDamage=1},{Defense=999},0,{CritRoll=1})
  expect.equal(result.Amount,1)
 end)

 -- Final stats clamp invalid negative and out-of-range values.
 t.test('clamps final stat boundaries',function()
  local result=CombatMath.CalculateFinalStats(attacker,{MaxHealth=-1000,Defense=-100,CritChance=5,CritDamage=-9})
  expect.equal(result.MaxHealth,1);expect.equal(result.Defense,0);expect.equal(result.CritChance,1);expect.equal(result.CritDamage,1)
 end)

 -- Invalid input fails predictably.
 t.test('rejects invalid stat tables',function()
  expect.throws(function() CombatMath.CalculateDamage(nil,defender,0,{CritRoll=1}) end)
 end)
end

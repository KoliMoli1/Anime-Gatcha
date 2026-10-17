return function(t)
 local Engine=require(game.ReplicatedStorage.AnimeCombatCore.Shared.BattleEngine)
 local expect=t.expect
 local defs={
  Fast={Classes={Speed=true},BaseStats={MaxHealth=100,Attack=10,Defense=5,Speed=90,CritChance=0,CritDamage=1}},
  Mid={Classes={Attack=true},BaseStats={MaxHealth=100,Attack=10,Defense=5,Speed=50,CritChance=0,CritDamage=1}},
  Slow={Classes={Defense=true},BaseStats={MaxHealth=100,Attack=10,Defense=5,Speed=20,CritChance=0,CritDamage=1}},
 }

 -- Queue order follows descending speed across both teams.
 t.test('sorts all living actions by speed',function()
  local q=Engine.BuildActionQueue({'Slow','Mid','Fast'},{'Mid','Slow','Fast'},{100,100,100},{100,100,100},{'Attack','Attack','Attack'},{'Attack','Attack','Attack'},defs)
  expect.equal(q[1].CharacterId,'Fast');expect.equal(q[1].Side,'Player');expect.equal(q[2].CharacterId,'Fast');expect.equal(q[2].Side,'Enemy');expect.equal(q[6].CharacterId,'Slow')
 end)

 -- KO characters never enter the action queue.
 t.test('excludes defeated actors from action queue',function()
  local q=Engine.BuildActionQueue({'Fast','Mid','Slow'},{'Fast','Mid','Slow'},{0,100,100},{100,0,100},{},{},defs)
  expect.equal(#q,4)
 end)

 -- A living taunter overrides the requested target.
 t.test('taunt redirects targeting',function() expect.equal(Engine.ResolveTarget(1,{100,100,100},3),3) end)

 -- A dead requested target retargets to the first living slot.
 t.test('retargets when selected target is defeated',function() expect.equal(Engine.ResolveTarget(2,{0,0,50},nil),3) end)

 -- Battle completion reports victory, defeat, and an unfinished battle.
 t.test('detects battle winner',function()
  expect.equal(Engine.Winner({10,0,0},{0,0,0}),'Player');expect.equal(Engine.Winner({0,0,0},{10,0,0}),'Enemy');expect.equal(Engine.Winner({10,0,0},{10,0,0}),nil)
 end)

 -- Haste and disruption alter effective speed without dropping below one.
 t.test('applies speed status modifiers',function()
  expect.equal(Engine.ModifiedSpeed(defs.Fast,2,0),135);expect.equal(Engine.ModifiedSpeed(defs.Fast,0,2),58);expect.equal(Engine.ModifiedSpeed(defs.Fast,2,2),87)
 end)

 -- Status-aware queues use effective rather than base speed.
 t.test('sorts using haste and disruption',function()
  local q=Engine.BuildActionQueue({'Slow','Mid','Fast'},{'Fast','Mid','Slow'},{100,100,100},{100,100,100},{},{},defs,{Player={Haste={[1]=2},Disrupted=0},Enemy={Haste={},Disrupted=2}})
  expect.equal(q[1].CharacterId,'Slow');expect.equal(q[1].Side,'Player')
 end)
end

return function(t)
 local Rules=require(game.ReplicatedStorage.AnimeCombatCore.Shared.GachaRules)
 local expect=t.expect

 -- Every inclusive boundary maps to the intended training character.
 t.test('maps roll range boundaries',function()
  expect.equal(Rules.CharacterForRoll(1),'TrainingSupport');expect.equal(Rules.CharacterForRoll(699),'TrainingSupport')
  expect.equal(Rules.CharacterForRoll(700),'TrainingDisrupt');expect.equal(Rules.CharacterForRoll(799),'TrainingDisrupt')
  expect.equal(Rules.CharacterForRoll(800),'TrainingSpeed');expect.equal(Rules.CharacterForRoll(899),'TrainingSpeed')
  expect.equal(Rules.CharacterForRoll(900),'TrainingDefense');expect.equal(Rules.CharacterForRoll(949),'TrainingDefense')
  expect.equal(Rules.CharacterForRoll(950),'TrainingAttack');expect.equal(Rules.CharacterForRoll(1000),'TrainingAttack')
 end)

 -- Invalid or out-of-range rolls never grant a character.
 t.test('rejects invalid roll values',function()
  expect.equal(Rules.CharacterForRoll(0),nil);expect.equal(Rules.CharacterForRoll(1001),nil);expect.equal(Rules.CharacterForRoll(1.5),nil)
 end)

 -- Duplicate compensation cannot create premium roll currency.
 t.test('duplicates always have positive net cost',function()
  expect.truthy(Rules.DuplicateReward>=0);expect.truthy(Rules.DuplicateReward<Rules.RollCost);expect.truthy(Rules.DuplicateNetCost()>0)
 end)
end

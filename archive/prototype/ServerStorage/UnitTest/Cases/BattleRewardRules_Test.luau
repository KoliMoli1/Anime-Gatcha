return function(t)
 local Rules=require(game.ReplicatedStorage.AnimeCombatCore.Shared.BattleRewardRules)
 local expect=t.expect
 -- Outcomes map to positive, bounded server-owned coin rewards.
 t.test('maps supported outcomes',function()
  expect.equal(Rules.CoinsForOutcome('Win'),30);expect.equal(Rules.CoinsForOutcome('Loss'),10);expect.equal(Rules.CoinsForOutcome('Draw'),15);expect.equal(Rules.CoinsForOutcome('Hack'),nil)
 end)
 -- Claim identifiers accept only bounded server-safe characters.
 t.test('validates claim identifiers',function()
  expect.truthy(Rules.IsValidClaimId('PvE_12345678'));expect.falsy(Rules.IsValidClaimId('short'));expect.falsy(Rules.IsValidClaimId('bad claim id!'))
 end)
end

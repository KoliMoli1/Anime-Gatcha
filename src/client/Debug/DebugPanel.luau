--!nonstrict
-- Playtest debug panel (Iris). F3 toggles it in Studio and for group admins.
-- Shows the live battle state the client knows: round, phase, energy, units, effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.Parent.Battle.BattleState)

local DebugPanel = {}

local function allowed(): boolean
	return RunService:IsStudio() or Players.LocalPlayer:GetAttribute("IsAdmin") == true
end

function DebugPanel.Start()
	local visible = false
	local Iris = nil
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F3 or not allowed() then
			return
		end
		visible = not visible
		if visible and not Iris then
			Iris = require(ReplicatedStorage.Packages.Iris).Init(nil, nil, false)
			Iris:Connect(function()
				if not visible then
					return
				end
				Iris.Window({ "Battle debug (F3)" })
				local snapshot = State.snapshot()
				Iris.Text({ `Battle: {State.battleId() or "none"}   Phase: {State.phase()}   Side: {State.side()}` })
				if snapshot then
					Iris.Text({
						`Round {snapshot.Round}/{snapshot.MaxRounds}   Energy {snapshot.Teams[1].Energy} vs {snapshot.Teams[2].Energy}`,
					})
					Iris.Text({
						`Deadline in {math.floor(State.deadline() - workspace:GetServerTimeNow())}s   Planned cost {State.plannedCost()}`,
					})
					for side, team in snapshot.Teams do
						Iris.SeparatorText({ if side == State.side() then "Your team" else "Enemy team" })
						for slot, unit in team.Units do
							local hp = State.hp()[side] and State.hp()[side][slot] or unit.HP
							local speed = if unit.Speed then tostring(unit.Speed) else "?"
							Iris.Text({
								`{slot}. {unit.Name} [{unit.Class}] HP {hp}/{unit.MaxHP} SPD {speed} ATK {math.floor(
									unit.Stats.ATK
								)} DEF {math.floor(unit.Stats.DEF)}`,
							})
							for _, effect in unit.Effects do
								Iris.Text({
									`     {effect.Key}  {effect.Stat or effect.Kind} {effect.Amount}  ({effect.Turns}t)`,
								})
							end
						end
					end
				end
				Iris.End()
			end)
		end
	end)
end

return DebugPanel

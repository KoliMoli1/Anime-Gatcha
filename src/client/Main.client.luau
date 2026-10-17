--!strict
-- Client entry point. Prototype menus in StarterGui (summon, team select,
-- collection, PvP queue) still run until Phases 4-5 replace them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Admin console (F2). The server rejects commands from non-admins.
local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient") :: ModuleScript) :: any
CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

local Battle = script.Parent:WaitForChild("Battle")
local BattleController = require(Battle:WaitForChild("BattleController") :: ModuleScript) :: any
local MainHud = require(script.Parent:WaitForChild("Hud"):WaitForChild("MainHud") :: ModuleScript) :: any
local DebugPanel = require(script.Parent:WaitForChild("Debug"):WaitForChild("DebugPanel") :: ModuleScript) :: any

BattleController.Start()
MainHud.Start()
DebugPanel.Start()

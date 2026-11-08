--!strict
-- Client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Admin console (F2). The server rejects commands from non-admins.
local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient") :: ModuleScript) :: any
CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

local Battle = script.Parent:WaitForChild("Battle")
local Hud = script.Parent:WaitForChild("Hud")
local BattleController = require(Battle:WaitForChild("BattleController") :: ModuleScript) :: any
local ProfileState = require(Hud:WaitForChild("ProfileState") :: ModuleScript) :: any
local MainHud = require(Hud:WaitForChild("MainHud") :: ModuleScript) :: any
local TeamFollowers = require(Hud:WaitForChild("TeamFollowers") :: ModuleScript) :: any
local DebugPanel = require(script.Parent:WaitForChild("Debug"):WaitForChild("DebugPanel") :: ModuleScript) :: any

ProfileState.Start()
BattleController.Start()
MainHud.Start()
TeamFollowers.Start()
DebugPanel.Start()

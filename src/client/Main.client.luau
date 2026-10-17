--!strict
-- Client entry point. The prototype menus in StarterGui still drive the UI
-- until Phase 2; this script sets up shared client tooling.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Admin console. The server rejects commands from non-admins.
local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient") :: ModuleScript) :: any
CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

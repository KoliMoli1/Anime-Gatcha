--!strict
-- Server entry point. Services start in dependency order.
local Services = script.Parent.Services

local order = {
	"ProfileService",
	"RosterService",
	"GachaService",
	"PveService",
	"PvPQueueService",
	"AdminService",
}

for _, name in order do
	local service = require(Services:FindFirstChild(name) :: ModuleScript) :: any
	service.Start()
end

print(`[Server] {#order} services started.`)

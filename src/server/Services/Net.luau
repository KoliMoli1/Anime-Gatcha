--!strict
-- One place to declare remotes. Every client call is rate limited and validated
-- before the handler runs; rejected calls never reach game logic.
-- Remotes live in ReplicatedStorage.Remotes and are created on server start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end
local remotes = folder :: Folder

export type Options = {
	-- Sustained calls per second and short burst allowance.
	Rate: number?,
	Burst: number?,
	-- Returns true when the arguments are acceptable.
	Validate: ((...any) -> boolean)?,
}

type Bucket = { Tokens: number, Updated: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, name: string, options: Options): boolean
	local rate = options.Rate or 5
	local burst = options.Burst or rate * 2
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { Tokens = burst, Updated = now }
		perPlayer[name] = bucket
	end
	bucket.Tokens = math.min(burst, bucket.Tokens + (now - bucket.Updated) * rate)
	bucket.Updated = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

local function getOrCreate(className: string, name: string): Instance
	local existing = remotes:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	elseif existing then
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end

function Net.event(name: string): RemoteEvent
	return getOrCreate("RemoteEvent", name) :: RemoteEvent
end

-- RemoteFunction handler. Rejections return { success = false, message = ... }.
function Net.handle(name: string, options: Options, handler: (Player, ...any) -> any): RemoteFunction
	local remote = getOrCreate("RemoteFunction", name) :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, ...)
		if not allow(player, name, options) then
			return { success = false, message = "Slow down a little." }
		end
		if options.Validate and not options.Validate(...) then
			return { success = false, message = "Invalid request." }
		end
		return handler(player, ...)
	end
	return remote
end

-- RemoteEvent listener with the same protections.
function Net.listen(name: string, options: Options, handler: (Player, ...any) -> ()): RemoteEvent
	local remote = Net.event(name)
	remote.OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, name, options) then
			return
		end
		if options.Validate and not options.Validate(...) then
			return
		end
		handler(player, ...)
	end)
	return remote
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return Net

-- Paste into Studio (command bar or MCP) while `python -m http.server 34877 --bind 127.0.0.1`
-- serves the build folder. Replaces every Rojo-managed root with the manifest's version.
-- HTTP is switched on only for the fetch and restored afterwards.
local HttpService = game:GetService("HttpService")
local PORT = 34877

local wasEnabled = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local ok, body = pcall(HttpService.GetAsync, HttpService, `http://127.0.0.1:{PORT}/manifest.json`, true)
HttpService.HttpEnabled = wasEnabled
if not ok then
	error("Sync fetch failed: " .. tostring(body))
end

local manifest = HttpService:JSONDecode(body)

local function build(node)
	local instance = Instance.new(node.c)
	instance.Name = node.n
	if node.s then
		(instance :: any).Source = node.s
	end
	for _, child in node.k or {} do
		build(child).Parent = instance
	end
	return instance
end

local function resolve(path: string): Instance
	local current: Instance = game
	for segment in string.gmatch(path, "[^%.]+") do
		local nextInstance = current:FindFirstChild(segment)
		if not nextInstance and current == game then
			nextInstance = game:GetService(segment)
		end
		assert(nextInstance, "Missing sync parent " .. path)
		current = nextInstance
	end
	return current
end

local report = {}
for _, root in manifest.roots do
	local parent = resolve(root.parent)
	local fresh = build(root.node)
	local old = parent:FindFirstChild(root.node.n)
	if old then
		old:Destroy()
	end
	fresh.Parent = parent
	table.insert(report, `{root.parent}.{root.node.n}`)
	task.wait()
end
return "Synced: " .. table.concat(report, ", ")

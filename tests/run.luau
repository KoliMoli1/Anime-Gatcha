-- Headless test runner: `lune run tests/run` from the repo root.
-- Each tests/*.spec.luau returns function(t) and uses t.test / t.expect* helpers.
local fs = require("@lune/fs")
local process = require("@lune/process")

local passed, failed = 0, 0
local failures = {}

local function makeHelpers(fileName)
	local t = {}
	function t.test(name, fn)
		local ok, err = pcall(fn)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, `{fileName} :: {name}\n    {err}`)
		end
	end
	function t.equal(actual, expected, label)
		if actual ~= expected then
			error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
		end
	end
	function t.near(actual, expected, tolerance, label)
		if math.abs(actual - expected) > tolerance then
			error(`{label or "value"}: expected {expected} +/- {tolerance}, got {actual}`, 2)
		end
	end
	function t.truthy(value, label)
		if not value then
			error(`{label or "value"} should be truthy`, 2)
		end
	end
	function t.falsy(value, label)
		if value then
			error(`{label or "value"} should be falsy`, 2)
		end
	end
	return t
end

local files = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(files, name)
	end
end
table.sort(files)

for _, name in files do
	local spec = require(`./{string.gsub(name, "%.luau$", "")}`)
	spec(makeHelpers(name))
end

print(`{passed} passed, {failed} failed`)
for _, failure in failures do
	print("FAIL " .. failure)
end
process.exit(if failed > 0 then 1 else 0)

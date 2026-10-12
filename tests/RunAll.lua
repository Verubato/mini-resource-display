-- Entry point for the MiniResourceDisplay test suite. Run from the repository root:
--
--   lua tests/RunAll.lua
--
-- Requirements: Lua 5.1. The shared harness lives in the build submodule, so a fresh clone
-- needs `git submodule update --init` first.

package.path = "build/Lua/?.lua;tests/Helpers/?.lua;tests/?.lua;" .. package.path

-- The shared mock does not define the Forever project constant. It has to exist before the mock
-- loads, because installing a client clears every global that was not there at that point.
_G.WOW_PROJECT_CAMELOT = 18

io.write("MiniResourceDisplay - unit tests\n")
io.write("======================================\n")

local testFiles = {
	"tests/TestPowerTick.lua",
	"tests/TestConfig.lua",
	"tests/TestBarGroup.lua",
	"tests/TestClassPower.lua",
	-- Last: the smoke test installs a clean client over whatever the suites above left.
	"tests/TestSmoke.lua",
}

local loadErrors = {}

for _, path in ipairs(testFiles) do
	io.write("\n[" .. path .. "]\n")

	local chunk, err = loadfile(path)

	if chunk then
		local ok, runError = pcall(chunk)

		if not ok then
			io.write("  ERROR while running " .. path .. ":\n  " .. tostring(runError) .. "\n")
			loadErrors[#loadErrors + 1] = path .. ": " .. tostring(runError)
		end
	else
		io.write("  ERROR loading " .. path .. ":\n  " .. tostring(err) .. "\n")
		loadErrors[#loadErrors + 1] = path .. ": " .. tostring(err)
	end
end

local fw = require("TestFramework")
local passed = fw.summary()

if #loadErrors > 0 then
	io.write("\nFile-load errors:\n")

	for _, message in ipairs(loadErrors) do
		io.write("  " .. message .. "\n")
	end

	passed = false
end

os.exit(passed and 0 or 1)

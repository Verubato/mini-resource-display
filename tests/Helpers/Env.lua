-- Loads MiniResourceDisplay into a mocked client and hands the tests the clock and the power
-- meter, which are the only two inputs the tick tracker has.
--
-- Nothing in the WoW API exposes the server's regen tick phase. The tracker infers it by
-- polling power every frame and deciding, from the size of each gain, whether it was the
-- server ticking or something else handing out resource. That inference is what these helpers
-- exist to drive: an arbitrary clock and an arbitrary power reading, sampled on demand.

local harness = require("AddonHarness")

local M = {}

---Builds a client with the addon loaded, logged in, and running a Classic flavour.
---@return table env
function M.Build()
	-- The tick tracker only offers itself on the flavours that regen in discrete lumps, and
	-- it reads the project id when asked rather than at load, so this can be set either side.
	_G.WOW_PROJECT_ID = _G.WOW_PROJECT_WRATH_CLASSIC

	local context = harness.Load("MiniResourceDisplay")

	local env = {
		Addon = context.Addon,
		Context = context,
		Time = 500,
		PowerType = _G.Enum.PowerType.Mana,
		Power = 0,
		Max = 100,
	}

	_G.GetTime = function()
		return env.Time
	end

	_G.UnitPowerType = function()
		return env.PowerType, "MANA"
	end

	_G.UnitPower = function()
		return env.Power
	end

	_G.UnitPowerMax = function()
		return env.Max
	end

	harness.Login(context)

	env.Tick = context.Addon.PowerTick

	-- Controls

	function env.Advance(seconds)
		env.Time = env.Time + seconds
	end

	---Sets the power meter and samples it, which is one frame of the real poller.
	function env.PollAt(power)
		env.Power = power
		env.Tick:Poll()
	end

	---Samples without changing anything, for letting time pass.
	function env.Poll()
		env.Tick:Poll()
	end

	---Switches resource, which is what a druid shapeshifting looks like from here.
	function env.UsePowerType(powerType, max)
		env.PowerType = powerType
		env.Max = max or env.Max
	end

	---Establishes a baseline reading. The first sample after a reset only records where the
	---meter is; a gain needs two samples to exist at all.
	function env.Baseline(power)
		env.Tick:Reset()
		env.PollAt(power)
	end

	return env
end

return M

-- The power tick tracker infers where the server's two-second regen tick falls, from nothing
-- but the size of each power gain. Everything it has to get right is a judgement call about
-- an event it cannot see:
--
--   * which gains are the server ticking, and which are a potion, a proc or an ability refund
--   * when spirit regen is suppressed by the five second rule
--   * what to show when it genuinely does not know - which must be nothing, not a guess
--
-- The last one is the interesting case. Carrying the old cadence across a cast is what once
-- made the first tick after spending mana land in the wrong place, and the fix was to stop
-- claiming to know rather than to guess better.

local fw = require("TestFramework")
local Env = require("Env")

local TICK_PERIOD = 2.0
local FSR_DURATION = 5.0

fw.describe("MiniResourceDisplay - client support", function()
	local env

	fw.before_each(function()
		env = Env.Build()
	end)

	fw.it("offers itself on the flavours that regen in ticks", function()
		for _, project in ipairs({
			_G.WOW_PROJECT_CLASSIC,
			_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC,
			_G.WOW_PROJECT_WRATH_CLASSIC,
			_G.WOW_PROJECT_CATACLYSM_CLASSIC,
			_G.WOW_PROJECT_MISTS_CLASSIC,
		}) do
			_G.WOW_PROJECT_ID = project

			fw.truthy(env.Tick:IsSupported(), "project " .. tostring(project))
		end
	end)

	fw.it("stays hidden on retail, where regen is continuous", function()
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_MAINLINE

		fw.falsy(env.Tick:IsSupported(), "retail has no tick to point at")
	end)
end)

fw.describe("MiniResourceDisplay - the five second rule", function()
	local env

	fw.before_each(function()
		env = Env.Build()
		env.UsePowerType(_G.Enum.PowerType.Mana, 1000)
		env.Baseline(1000)
	end)

	fw.it("starts the rule when mana is spent", function()
		fw.falsy(env.Tick:InFiveSecondRule(), "not in the rule before spending")

		env.PollAt(800)

		fw.truthy(env.Tick:InFiveSecondRule(), "spending mana starts the rule")
		fw.eq(env.Tick:GetFiveSecondRuleRemaining(), FSR_DURATION, "full duration remaining")
	end)

	fw.it("counts the rule down and lets it expire", function()
		env.PollAt(800)

		env.Advance(3)
		fw.eq(env.Tick:GetFiveSecondRuleRemaining(), 2, "remaining after 3 seconds")

		env.Advance(2)
		fw.eq(env.Tick:GetFiveSecondRuleRemaining(), 0, "expired exactly on the boundary")
		fw.falsy(env.Tick:InFiveSecondRule(), "no longer suppressed")
	end)

	fw.it("never reports a negative remainder", function()
		env.PollAt(800)
		env.Advance(60)

		fw.eq(env.Tick:GetFiveSecondRuleRemaining(), 0, "long past expiry")
	end)

	fw.it("does not apply the rule to energy", function()
		-- Energy has no spirit regen to suppress, so spending it starts nothing.
		env.UsePowerType(_G.Enum.PowerType.Energy, 100)
		env.Baseline(100)

		env.PollAt(60)

		fw.falsy(env.Tick:InFiveSecondRule(), "energy is never in the five second rule")
	end)

	fw.it("stops pointing anywhere until a real tick shows where the cadence went", function()
		-- Spending mana moves the server's timer somewhere that cannot be worked out from
		-- here. Showing the old phase is worse than showing nothing.
		--
		-- Starting below full: a topped-up bar reports no progress regardless, which would
		-- hide the distinction this test is about.
		env.Baseline(900)

		env.Advance(0.5)
		env.PollAt(950)
		fw.eq(env.Tick:GetProgress(), 0, "a spirit tick anchored the cadence")

		env.Advance(0.5)
		env.PollAt(850)
		fw.is_nil(env.Tick:GetProgress(), "spending mana takes the marker off screen")

		-- Once the rule lapses, the next gain is a spirit tick and re-establishes the phase.
		env.Advance(FSR_DURATION + 0.1)
		env.PollAt(880)

		fw.eq(env.Tick:GetProgress(), 0, "the first tick after the rule re-anchors it")
	end)

	fw.it("treats a gain during the rule as gear, not a tick", function()
		env.PollAt(900)

		-- mp5 gear and items run on their own schedule, so a gain here says nothing about
		-- where the server's spirit tick falls.
		env.Advance(1)
		env.PollAt(950)

		fw.is_nil(env.Tick:GetProgress(), "an mp5 tick does not re-anchor the cadence")
	end)
end)

fw.describe("MiniResourceDisplay - identifying an energy tick", function()
	local env

	fw.before_each(function()
		env = Env.Build()
		env.UsePowerType(_G.Enum.PowerType.Energy, 100)
		env.Baseline(0)
	end)

	---Polls a gain and reports whether the tracker treated it as the server ticking, by
	---checking whether the cadence re-anchored to this moment.
	---
	---Reads the anchor rather than GetProgress because one of the cases below deliberately
	---fills the bar, and a full bar reports no progress whether or not a tick landed. Half a
	---second keeps every call well inside the period, so a free-run rollover can't be
	---mistaken for a detected tick.
	local function gainWasTick(amount)
		env.Advance(0.5)
		env.PollAt(env.Power + amount)
		return env.Tick.tickAt == env.Time
	end

	fw.it("accepts the standard twenty point tick", function()
		fw.truthy(gainWasTick(20), "20 energy")
	end)

	fw.it("accepts a tick a couple of points either side", function()
		-- Haste and rounding move it slightly; the tracker allows two points of slop.
		fw.truthy(gainWasTick(18), "18 energy")

		env.Baseline(0)
		fw.truthy(gainWasTick(22), "22 energy")
	end)

	fw.it("accepts a doubled tick, which is what Adrenaline Rush does", function()
		-- Adrenaline Rush changes how much each tick delivers, not how often they land.
		fw.truthy(gainWasTick(40), "40 energy")
	end)

	fw.it("rejects a refund that is neither a tick nor a doubled tick", function()
		-- Combat Potency and Relentless Strikes hand out energy off-schedule. Latching onto
		-- one is what makes the marker jump around mid-fight.
		fw.falsy(gainWasTick(8), "8 energy")

		env.Baseline(0)
		fw.falsy(gainWasTick(60), "60 energy")
	end)

	fw.it("accepts a tick trimmed short by the energy bar filling up", function()
		-- A tick that would overflow arrives smaller than usual, so it has to be judged by
		-- where it landed rather than by its size.
		env.Baseline(95)

		fw.truthy(gainWasTick(5), "5 energy that reached the cap")
	end)

	fw.it("still rejects a large refund that happens to fill the bar", function()
		-- Thistle Tea also ends at the cap. The cap rule is bounded above so it cannot
		-- swallow a refund several times the size of a tick.
		env.Baseline(0)

		fw.falsy(gainWasTick(100), "a full bar from empty is not a tick")
	end)
end)

fw.describe("MiniResourceDisplay - cadence and progress", function()
	local env

	fw.before_each(function()
		env = Env.Build()
		env.UsePowerType(_G.Enum.PowerType.Energy, 100)
		env.Baseline(0)
	end)

	fw.it("reports progress through the period as a fraction", function()
		env.PollAt(20)
		fw.eq(env.Tick:GetProgress(), 0, "just after a tick")

		env.Advance(1)
		env.Poll()
		fw.eq(env.Tick:GetProgress(), 0.5, "halfway through the period")
	end)

	fw.it("keeps the marker moving when it detects nothing at all", function()
		-- Resource capped, a tick filtered out, mana held down by the five second rule: the
		-- cadence free-runs so the marker never stalls, and the next real tick pulls it back.
		env.PollAt(20)
		fw.eq(env.Tick:GetProgress(), 0, "anchored")

		env.Advance(TICK_PERIOD + 0.1)
		env.Poll()

		local progress = env.Tick:GetProgress()

		fw.truthy(progress ~= nil and progress < 0.2, "rolled over rather than running past the end")
	end)

	fw.it("points nowhere when the bar is already full", function()
		-- Nothing is on the way, so there is no tick to count down to.
		env.PollAt(20)
		fw.not_nil(env.Tick:GetProgress(), "anchored below the cap")

		env.PollAt(100)

		fw.is_nil(env.Tick:GetProgress(), "at the cap")
	end)

	fw.it("points nowhere for a resource that does not regenerate", function()
		-- Rage and runic power do not tick, so the whole feature has nothing to say.
		env.UsePowerType(_G.Enum.PowerType.Rage, 100)
		env.Baseline(50)
		env.PollAt(60)

		fw.is_nil(env.Tick:GetProgress(), "rage has no tick")
	end)

	fw.it("restarts the cadence when the resource changes", function()
		-- A druid shifting into cat form swaps mana for energy; the old phase means nothing.
		env.PollAt(20)

		env.Advance(1)
		env.UsePowerType(_G.Enum.PowerType.Energy, 100)
		env.Poll()

		env.UsePowerType(_G.Enum.PowerType.Mana, 1000)
		env.PollAt(500)

		-- Mana starts out waiting for a tick to show where the cadence is.
		fw.is_nil(env.Tick:GetProgress(), "no phase carried across the swap")
	end)
end)

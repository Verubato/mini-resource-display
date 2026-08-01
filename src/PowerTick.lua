local _, addon = ...

-- Classic-lineage servers hand out power regen as a discrete lump every two seconds.
-- Nothing in the API exposes the server's tick phase, so it's inferred by watching for the
-- gains themselves: poll every frame rather than react to events, identify a tick by how
-- much it delivers rather than by when it lands, and let the cadence free-run so the marker
-- never stalls.
local TICK_PERIOD = 2.0

-- Spirit regen is suppressed for five seconds after mana is spent.
local FSR_DURATION = 5.0

-- Energy arrives 20 at a time, doubled by Adrenaline Rush. Everything else that hands out
-- energy - Thistle Tea, Combat Potency, Relentless Strikes - misses both windows and gets
-- ignored, which is what stops the marker jumping around mid-fight.
local ENERGY_PER_TICK = 20
local ENERGY_TICK_SLOP = 2

-- Recent gains kept for the /mrd tick readout. Diagnosing a bad lock means seeing the real
-- cadence, and nothing else exposes it.
local GAIN_HISTORY = 8

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

-- Only mana and energy tick. Rage and runic power don't regen at all, and no Classic
-- player class uses focus.
local TICKING_POWER_TYPES = {
	[MANA] = true,
	[ENERGY] = true,
}

-- The flavours that regen in ticks, listed rather than inferred from "isn't retail" so a
-- client this addon has never been tried on can't quietly turn the feature on. A new Classic
-- flavour has to be added here or the ticker simply won't offer itself there.
-- Named globals rather than their numeric values, and built with pairs so a constant the
-- running client doesn't define is skipped instead of truncating the list.
local CLASSIC_PROJECT_IDS = {}

for _, project in pairs({
	WOW_PROJECT_CLASSIC,
	WOW_PROJECT_BURNING_CRUSADE_CLASSIC,
	WOW_PROJECT_WRATH_CLASSIC,
	WOW_PROJECT_CATACLYSM_CLASSIC,
	WOW_PROJECT_MISTS_CLASSIC,
}) do
	CLASSIC_PROJECT_IDS[project] = true
end

local M = { gains = {} }
local poller

addon.PowerTick = M

---Whether this client regenerates power in discrete ticks at all. Retail regen is
---continuous, so there is no tick to point at and the whole feature is hidden there.
---@return boolean
function M:IsSupported()
	return CLASSIC_PROJECT_IDS[WOW_PROJECT_ID] == true
end

---Whether a gain is the server tick rather than a proc, a potion or an ability refund.
local function IsEnergyTick(gained, power, max)
	if math.abs(gained - ENERGY_PER_TICK) <= ENERGY_TICK_SLOP then
		return true
	end

	-- Adrenaline Rush doubles what each tick delivers rather than how often they land.
	if math.abs(gained - ENERGY_PER_TICK * 2) <= ENERGY_TICK_SLOP then
		return true
	end

	-- A tick that would overflow gets trimmed short, so judge that one by where it landed.
	-- Bounded above so Thistle Tea's much larger refund can't sneak through the same door.
	return max > 0 and power >= max and gained < ENERGY_PER_TICK * 2 + ENERGY_TICK_SLOP
end

---Restarts the cadence from now. Used when the phase can't be carried over - zoning, a
---power type swap, or the ticker being switched on.
function M:Reset()
	self.power = nil
	self.tickAt = GetTime()
	self.fsrEndsAt = nil
	-- Mana only; see Poll. Energy free-runs instead so it still degrades to an approximation
	-- on clients where the tick amount doesn't match what's expected.
	self.awaitingTick = self.powerType == MANA
end

---Seconds left of the five second rule, 0 when spirit regen is flowing.
---@return number
function M:GetFiveSecondRuleRemaining()
	if not self.fsrEndsAt or self.powerType ~= MANA then
		return 0
	end

	local remaining = self.fsrEndsAt - GetTime()

	return remaining > 0 and remaining or 0
end

---@return boolean
function M:InFiveSecondRule()
	return self:GetFiveSecondRuleRemaining() > 0
end

---Samples power and advances the cadence. Runs every frame while the ticker is on:
---an event round trip lands a frame or more late, and that lag is the difference between
---the marker resetting when power arrives and resetting slightly after it.
function M:Poll()
	local powerType = UnitPowerType("player")

	if powerType ~= self.powerType then
		self.powerType = powerType
		self:Reset()
	end

	if not TICKING_POWER_TYPES[powerType] then
		return
	end

	local power = UnitPower("player", powerType) or 0
	local previous = self.power
	local now = GetTime()

	self.power = power

	if previous == nil then
		return
	end

	local isTick = false

	if power > previous then
		local gained = power - previous

		self.gains[#self.gains + 1] = { at = now, amount = gained }

		if #self.gains > GAIN_HISTORY then
			table.remove(self.gains, 1)
		end

		if powerType == ENERGY then
			isTick = IsEnergyTick(gained, power, UnitPowerMax("player", powerType) or 0)
		else
			-- Outside the five second rule every mana gain is a spirit tick. Inside it, any
			-- gain is mp5 gear or an item, which runs on its own schedule.
			isTick = not self:InFiveSecondRule()

			if isTick then
				self.awaitingTick = false
			end
		end
	elseif power < previous and powerType == MANA then
		-- Read the five second rule off the drop rather than off cast events, so it covers
		-- every way of spending mana without needing per-spell cost lookups.
		self.fsrEndsAt = now + FSR_DURATION

		-- Spending mana moves the server's tick timer somewhere that can't be worked out from
		-- here, so stop claiming to know where it is. Carrying the old phase across the five
		-- second rule is what made the first tick after a cast land in the wrong place; the
		-- marker stays hidden now until a real tick shows where the cadence actually went.
		self.awaitingTick = true
	end

	-- The cadence free-runs. When a whole period passes with nothing detected - resource
	-- capped, a tick filtered out, mana held down by the five second rule - roll over anyway
	-- so the marker keeps moving, and let the next real tick pull it back into phase.
	if now >= self.tickAt + TICK_PERIOD then
		isTick = true
	end

	if isTick then
		self.tickAt = now
	end
end

---Starts or stops polling. Off by default, so a client with the ticker disabled does no
---per-frame work at all.
function M:SetEnabled(enabled)
	if not self:IsSupported() then
		return
	end

	if not poller then
		poller = CreateFrame("Frame")
		poller:Hide()
		poller:SetScript("OnUpdate", function()
			M:Poll()
		end)
	end

	if not enabled then
		poller:Hide()
		return
	end

	if not poller:IsShown() then
		self:Reset()
		poller:Show()
	end
end

---Progress through the current tick: 0 just after one lands, approaching 1 just before
---the next. Nil when there is no tick to point at.
---@return number?
function M:GetProgress()
	if not self.tickAt or not self.powerType or not TICKING_POWER_TYPES[self.powerType] then
		return nil
	end

	if self.awaitingTick then
		return nil
	end

	-- A full resource has nothing on the way.
	local max = UnitPowerMax("player", self.powerType) or 0

	if max > 0 and (UnitPower("player", self.powerType) or 0) >= max then
		return nil
	end

	local elapsed = GetTime() - self.tickAt

	if elapsed < 0 then
		return 0
	end

	if elapsed > TICK_PERIOD then
		return 1
	end

	return elapsed / TICK_PERIOD
end

---Diagnostic snapshot for /mrd tick. The recent gain cadence is the thing that says whether
---the ticker is tracking real ticks or has latched onto something else.
---@return string[]
function M:Describe()
	if not self:IsSupported() then
		return { "Power tick: not supported on this client." }
	end

	local powerType = self.powerType
	local ticks = (powerType and TICKING_POWER_TYPES[powerType]) and true or false
	local lines = {
		string.format("Power type %s, ticks: %s, polling: %s",
			tostring(powerType), tostring(ticks), tostring(poller and poller:IsShown() or false)),
	}

	local progress = self:GetProgress()

	if progress then
		lines[#lines + 1] = string.format("Next tick in %.2fs", TICK_PERIOD - progress * TICK_PERIOD)
	elseif self.awaitingTick then
		lines[#lines + 1] = "Waiting for a tick to show where the cadence is"
	else
		lines[#lines + 1] = "Nothing to show (at full power, or power type doesn't tick)"
	end

	lines[#lines + 1] = string.format("Five second rule: %.1fs", self:GetFiveSecondRuleRemaining())

	if #self.gains > 1 then
		local intervals = {}
		local amounts = {}

		for i = 1, #self.gains do
			amounts[i] = tostring(self.gains[i].amount)

			if i > 1 then
				intervals[i - 1] = string.format("%.2f", self.gains[i].at - self.gains[i - 1].at)
			end
		end

		lines[#lines + 1] = "Gaps between gains: " .. table.concat(intervals, ", ")
		lines[#lines + 1] = "Amounts gained: " .. table.concat(amounts, ", ")
	else
		lines[#lines + 1] = "No gains recorded yet"
	end

	return lines
end

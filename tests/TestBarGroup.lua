-- Covers GetPowerColor's priority cascade, GetConfiguredTexture's LSM lookup, the FadeTo state
-- machine, and the incoming heal option, none of which TestConfig.lua or TestPowerTick.lua reach.
--
-- These are file-local to MiniResourceDisplay.lua, so every test drives them through the
-- events and public API a real client would use rather than reaching in directly.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---The player's container frame, the same one Config's texture test finds bars under.
---@return table?
local function FindContainer()
	return _G["MiniResourceDisplayFrame"]
end

---StatusBars are created against the container in a fixed order: health, incoming heal,
---regular absorb, overshield, then power last. The power bar is the only one still needed
---here, so it is picked out as whichever StatusBar was created last.
---@return table?
local function FindPowerBar()
	local container = FindContainer()
	local found

	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetObjectType() == "StatusBar" and frame:GetParent() == container then
			found = frame
		end
	end

	return found
end

---@return table?
local function FindHealthBar()
	local container = FindContainer()

	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetObjectType() == "StatusBar" and frame:GetParent() == container then
			return frame
		end
	end
end

fw.describe("GetPowerColor priority cascade", function()
	fw.it("uses the power type's colour when type colouring is on", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		-- Type colouring is on by default, so login already ran the bar through this branch.
		local r, g, b = FindPowerBar():GetStatusBarColor()

		-- WowMock's PowerBarColor answers every power type with the same generic shade, so
		-- this pins that shade rather than a real class colour.
		fw.eq(r, 0.5, "type colour red")
		fw.eq(g, 0.5, "type colour green")
		fw.eq(b, 0.5, "type colour blue")
	end)

	fw.it("uses the configured colour when type colouring is off", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		_G.MiniResourceDisplayDB.PowerUseTypeColor = false
		_G.MiniResourceDisplayDB.PowerColor = { 0.1, 0.2, 0.3 }
		context.Addon:Reload()

		local r, g, b = FindPowerBar():GetStatusBarColor()

		fw.eq(r, 0.1, "configured red")
		fw.eq(g, 0.2, "configured green")
		fw.eq(b, 0.3, "configured blue")
	end)

	fw.it("falls back to the built-in default when nothing is configured", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		_G.MiniResourceDisplayDB.PowerUseTypeColor = false
		_G.MiniResourceDisplayDB.PowerColor = nil
		context.Addon:Reload()

		local r, g, b = FindPowerBar():GetStatusBarColor()

		-- Pinned so a change to the shipped default is caught here rather than only in the
		-- config panel's own colour picker.
		fw.eq(r, 0.2, "default red")
		fw.eq(g, 0.6, "default green")
		fw.eq(b, 1.0, "default blue")
	end)
end)

fw.describe("GetConfiguredTexture", function()
	fw.it("resolves a registered LibSharedMedia name to its path", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
		fw.not_nil(lsm, "LibSharedMedia resolves under the mock")

		local name = "MiniResourceDisplay BarGroup Texture"
		local path = "Interface\\AddOns\\Test\\BarGroupTexture.tga"
		lsm:Register("statusbar", name, path)

		_G.MiniResourceDisplayDB.Texture = name
		context.Addon:Reload()

		local texture = FindHealthBar():GetStatusBarTexture()

		fw.eq(texture and texture:GetTexture(), path, "health bar drew the registered file")
	end)

	fw.it("falls back to the addon's own default when LibSharedMedia itself answers nothing", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
		local realFetch = lsm.Fetch
		lsm.Fetch = function()
			return nil
		end

		_G.MiniResourceDisplayDB.Texture = "MiniResourceDisplay Never Registered"

		local ok, err = pcall(function()
			context.Addon:Reload()

			local texture = FindHealthBar():GetStatusBarTexture()

			-- Pinned so a change to the shipped fallback is caught here too.
			fw.eq(texture and texture:GetTexture(), "Interface\\TARGETINGFRAME\\UI-StatusBar", "drew the addon's own fallback")
		end)

		lsm.Fetch = realFetch

		if not ok then
			error(err, 0)
		end
	end)
end)

fw.describe("FadeTo state machine", function()
	local context

	fw.before_each(function()
		context = harness.Load("MiniResourceDisplay")
		harness.Login(context)
	end)

	fw.it("fades in to full alpha on entering combat", function()
		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		local container = FindContainer()

		fw.truthy(container.IsShowing, "showing")
		fw.eq(container.TargetAlpha, 1, "target alpha")
		fw.truthy(container.FadeIn:IsPlaying(), "fade in playing")
		fw.falsy(container.FadeOut:IsPlaying(), "fade out not playing")
	end)

	fw.it("fades out to zero on leaving combat", function()
		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		WowMock.State.InCombat = false
		WowMock.FireEvent("PLAYER_REGEN_ENABLED")

		local container = FindContainer()

		fw.falsy(container.IsShowing, "not showing")
		fw.eq(container.TargetAlpha, 0, "target alpha")
		fw.truthy(container.FadeOut:IsPlaying(), "fade out playing")
		fw.falsy(container.FadeIn:IsPlaying(), "fade in stopped")
	end)

	fw.it("reversing direction mid-fade stops the running animation instead of stacking one", function()
		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		WowMock.State.InCombat = false
		WowMock.FireEvent("PLAYER_REGEN_ENABLED")

		local container = FindContainer()
		fw.truthy(container.FadeOut:IsPlaying(), "fade out started")

		-- Back into combat before the fade out finished.
		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		fw.falsy(container.FadeOut:IsPlaying(), "fade out was stopped rather than left running")
		fw.truthy(container.FadeIn:IsPlaying(), "fade in took over")
	end)

	fw.it("does not restart the animation for a repeated call with nothing changed", function()
		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		local container = FindContainer()

		-- Simulate the animation having already finished, the way OnFinished would leave it.
		container.FadeIn:Stop()

		-- Still in combat: nothing about the requested state changed, so this should be a
		-- no-op rather than replaying the animation.
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		fw.falsy(container.FadeIn:IsPlaying(), "fade in was not replayed")
	end)
end)

---The incoming heal bar is the second StatusBar parented to the container, after health.
---@return table?
local function FindIncomingHealBar()
	local container = FindContainer()
	local seen = 0

	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetObjectType() == "StatusBar" and frame:GetParent() == container then
			seen = seen + 1
			if seen == 2 then
				return frame
			end
		end
	end
end

fw.describe("Incoming heal prediction option", function()
	local realIncoming = _G.UnitGetIncomingHeals
	local realHealth = _G.UnitHealth

	fw.it("defaults to on and shows the bar", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		fw.eq(_G.MiniResourceDisplayDB.ShowIncomingHeal, true, "default")
		fw.truthy(FindIncomingHealBar():IsShown(), "bar shown")
	end)

	fw.it("hides the bar and skips the heal data when off", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		-- Missing health has to cover the heal, or the calculator caps it to 0 either way.
		_G.UnitHealth = function()
			return 50
		end
		_G.UnitGetIncomingHeals = function()
			return 50
		end
		_G.MiniResourceDisplayDB.ShowIncomingHeal = false
		context.Addon:Reload()

		local bar = FindIncomingHealBar()
		_G.UnitGetIncomingHeals = realIncoming
		_G.UnitHealth = realHealth

		fw.falsy(bar:IsShown(), "bar hidden")
		fw.eq(bar:GetValue(), 0, "no heal value pushed to the bar")
	end)

	fw.it("shows the bar again without a reload when turned back on", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		_G.MiniResourceDisplayDB.ShowIncomingHeal = false
		context.Addon:Reload()
		_G.MiniResourceDisplayDB.ShowIncomingHeal = true
		context.Addon:Reload()

		fw.truthy(FindIncomingHealBar():IsShown(), "bar shown again")
	end)
end)

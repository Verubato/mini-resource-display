-- Covers GetPowerColor's priority cascade, GetConfiguredTexture's LSM lookup, the FadeTo state
-- machine, the incoming heal option, the saved position, and the stagger bar, none of which
-- other suites reach.
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
---regular absorb, absorb backing, overshield, stagger, then power last.
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

-- How far below each anchor point the top edge sits, as a share of the frame's height.
local POINT_TOP_OFFSET = {
	TOPLEFT = 0, TOP = 0, TOPRIGHT = 0,
	LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
	BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1,
}

---The mock lays nothing out, so the top edge is read as an offset from the container's anchor.
---@param container table
---@return number
local function TopEdge(container)
	local point, _, _, _, y = container:GetPoint(1)
	return y + container:GetHeight() * POINT_TOP_OFFSET[point]
end

---Points both spec APIs at one spec, the way TestClassPower.lua does.
local function SetSpec(specId)
	_G.C_SpecializationInfo.GetSpecialization = function()
		return 1
	end
	_G.C_SpecializationInfo.GetSpecializationInfo = function()
		return specId
	end
end

-- Health and power rows plus the container's padding, with the default Gap of 0.
local DEFAULT_HEIGHT = 15 + 15 + 2 * 2
local DEFAULT_PET_HEIGHT = 15 + 2 * 2

fw.describe("Position", function()
	fw.it("puts the default top edge where the old centred display had it", function()
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "WARRIOR" })
		harness.Login(context)

		local db = _G.MiniResourceDisplayDB
		local container = FindContainer()

		fw.eq(container:GetHeight(), DEFAULT_HEIGHT, "default height")
		fw.eq(db.Point, "TOP", "anchored by its top edge")
		fw.eq(db.RelativePoint, "CENTER", "still measured from the screen centre")
		fw.eq(TopEdge(container), -140 + DEFAULT_HEIGHT / 2, "top edge of a display centred 140 px down")

		db.ShowPetBar = true
		context.Addon:Reload()

		local pet = _G["MiniResourceDisplayPetFrame"]

		fw.eq(db.Pet.Point, "TOP", "pet anchored by its top edge")
		fw.eq(pet:GetHeight(), DEFAULT_PET_HEIGHT, "default pet height")
		fw.eq(TopEdge(pet), -165 + DEFAULT_PET_HEIGHT / 2, "top edge of a pet bar centred 165 px down")
	end)

	fw.it("keeps the default top edge for a fresh install that logs in with a class power row", function()
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		local container = FindContainer()

		fw.eq(container:GetHeight(), DEFAULT_HEIGHT + _G.MiniResourceDisplayDB.ClassPower.Height, "row shown")
		fw.eq(TopEdge(container), -140 + DEFAULT_HEIGHT / 2, "the row hangs below the default top edge")
	end)

	fw.it("keeps the top edge in place when cat form adds the class power row", function()
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "DRUID" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		_G.UnitPowerType = function() return 0, "MANA" end
		harness.Login(context)

		local container = FindContainer()
		local top = TopEdge(container)
		local height = container:GetHeight()

		_G.UnitPowerType = function() return 3, "ENERGY" end
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.eq(container:GetHeight(), height + _G.MiniResourceDisplayDB.ClassPower.Height, "grew by the row")
		fw.eq(TopEdge(container), top, "top edge did not move")

		_G.UnitPowerType = function() return 0, "MANA" end
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.eq(container:GetHeight(), height, "shrank back")
		fw.eq(TopEdge(container), top, "top edge still did not move")
	end)

	fw.it("moves an old centred position onto the top edge once, without moving it", function()
		_G.MiniResourceDisplayDB = {
			Point = "CENTER",
			RelativeTo = "UIParent",
			RelativePoint = "CENTER",
			X = 12,
			Y = -200,
			ShowPetBar = true,
			Pet = { Point = "CENTER", RelativeTo = "UIParent", RelativePoint = "CENTER", X = 5, Y = -250 },
		}

		local context = harness.Load("MiniResourceDisplay", { class = "WARRIOR" })
		harness.Login(context)

		local db = _G.MiniResourceDisplayDB

		fw.eq(db.Point, "TOP", "saved point")
		fw.eq(db.RelativePoint, "CENTER", "relative point kept")
		fw.eq(db.X, 12, "x kept")
		fw.eq(db.Y, -200 + DEFAULT_HEIGHT / 2, "y moved up by half the height")
		fw.eq(TopEdge(FindContainer()), -200 + DEFAULT_HEIGHT / 2, "top edge where the centred one had it")

		fw.eq(db.Pet.Point, "TOP", "pet saved point")
		fw.eq(db.Pet.X, 5, "pet x kept")
		fw.eq(db.Pet.Y, -250 + DEFAULT_PET_HEIGHT / 2, "pet y moved up by half its height")

		-- A new height would move the top edge if a converted position were converted again.
		db.Height = 20
		context.Addon:Reload()

		fw.eq(db.Point, "TOP", "a second pass keeps the top point")
		fw.eq(db.Y, -200 + DEFAULT_HEIGHT / 2, "a second pass keeps y")
		fw.eq(TopEdge(FindContainer()), -200 + DEFAULT_HEIGHT / 2, "a second pass keeps the top edge")
	end)

	fw.it("uses the height at the time it converts, class power row included", function()
		_G.MiniResourceDisplayDB = { Point = "CENTER", RelativeTo = "UIParent", RelativePoint = "CENTER", X = 0, Y = -140 }

		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		local db = _G.MiniResourceDisplayDB
		local height = DEFAULT_HEIGHT + db.ClassPower.Height

		fw.eq(FindContainer():GetHeight(), height, "class power row counted")
		fw.eq(db.Y, -140 + height / 2, "top edge of the taller display")
	end)

	fw.it("keeps a bottom anchored position's left edge and lifts it by the full height", function()
		_G.MiniResourceDisplayDB = {
			Point = "BOTTOMLEFT",
			RelativeTo = "UIParent",
			RelativePoint = "BOTTOMLEFT",
			X = 300,
			Y = 200,
		}

		local context = harness.Load("MiniResourceDisplay", { class = "WARRIOR" })
		harness.Login(context)

		local db = _G.MiniResourceDisplayDB

		fw.eq(db.Point, "TOPLEFT", "saved point")
		fw.eq(db.RelativePoint, "BOTTOMLEFT", "relative point kept")
		fw.eq(db.X, 300, "x kept")
		fw.eq(db.Y, 200 + DEFAULT_HEIGHT, "y moved up by the height")
	end)

	fw.it("puts a dropped frame back on its top edge, and lock and reset still apply", function()
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "WARRIOR" })
		harness.Login(context)

		local db = _G.MiniResourceDisplayDB
		local container = FindContainer()

		-- The client re-anchors a dragged frame by a point of its own choosing.
		container:ClearAllPoints()
		container:SetPoint("CENTER", _G.UIParent, "CENTER", 40, -60)
		container:GetScript("OnDragStop")(container)

		fw.eq(db.Point, "TOP", "saved point")
		fw.eq(db.X, 40, "saved x")
		fw.eq(db.Y, -60 + DEFAULT_HEIGHT / 2, "saved y")
		fw.eq((container:GetPoint(1)), "TOP", "frame re-anchored")
		fw.eq(TopEdge(container), -60 + DEFAULT_HEIGHT / 2, "frame did not move")

		db.Locked = true
		context.Addon:Reload()
		fw.falsy(container:IsMovable(), "locked")

		_G.SlashCmdList.MINIRESOURCEDISPLAY("reset")

		fw.eq(db.Point, "TOP", "reset point")
		fw.eq(db.Y, -123, "reset y")
		fw.falsy(db.Locked, "reset unlocks")
		fw.truthy(container:IsMovable(), "movable again")
		fw.eq(TopEdge(container), -123, "frame back at the default")
	end)
end)

---Font strings are made for health, power, then stagger, so the stagger bar is the third bar
---one of them is centred on.
---@param container table? defaults to the player's container
---@return table? bar, table? text
local function FindStaggerBar(container)
	container = container or FindContainer()
	local seen = 0

	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetParent() == container then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region:GetObjectType() == "FontString" then
					local _, relativeTo = region:GetPoint(1)

					if type(relativeTo) == "table" and relativeTo:GetObjectType() == "StatusBar" then
						seen = seen + 1

						if seen == 3 then
							return relativeTo, region
						end
					end
				end
			end
		end
	end
end

local BREWMASTER = 268
local WINDWALKER = 269

---Current health sits below max so a bar ranged on max health reads differently from one
---ranged on current health.
---@param beforeLogin fun()? runs after the load installs a fresh mock, for globals it would reset
local function LoginWithStagger(classToken, specId, stagger, beforeLogin)
	local context = harness.Load("MiniResourceDisplay", { class = classToken })
	SetSpec(specId)

	if beforeLogin then
		beforeLogin()
	end

	_G.UnitStagger = function()
		return stagger
	end
	_G.UnitHealth = function()
		return 80
	end
	_G.UnitHealthMax = function()
		return 200
	end

	harness.Login(context)

	-- Saved variables carry over between tests, so an earlier test may have changed these.
	local db = _G.MiniResourceDisplayDB
	db.ShowStagger = true
	db.ShowText = true
	db.UsePercent = false
	db.HideTextSuffix = false
	db.ShowHealth = true
	db.ShowPower = true
	-- A Windwalker's chi row would otherwise come and go alongside the stagger row.
	db.ClassPower.Enabled = false
	context.Addon:Reload()

	return context
end

---@return number, number, number
local function StaggerColor()
	local r, g, b = FindStaggerBar():GetStatusBarColor()
	return r, g, b
end

fw.describe("Stagger bar", function()
	fw.it("defaults to on for a fresh install", function()
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "MONK" })
		SetSpec(BREWMASTER)
		harness.Login(context)

		fw.eq(_G.MiniResourceDisplayDB.ShowStagger, true, "default")
		fw.truthy(FindStaggerBar():IsShown(), "bar shown")
	end)

	fw.it("shows the staggered amount against max health for a Brewmaster", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		local bar = FindStaggerBar()
		local min, max = bar:GetMinMaxValues()

		fw.truthy(bar:IsShown(), "bar shown")
		fw.eq(bar:GetValue(), 40, "stagger value")
		fw.eq(min, 0, "starts at zero")
		fw.eq(max, 200, "ranged on max health")
	end)

	fw.it("sits under the power bar as its own row", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		local db = _G.MiniResourceDisplayDB
		local bar = FindStaggerBar()
		local point, relativeTo, relativePoint, x, y = bar:GetPoint(1)

		fw.eq(point, "TOPLEFT", "point")
		fw.truthy(relativeTo == FindPowerBar(), "anchored to the power bar")
		fw.eq(relativePoint, "BOTTOMLEFT", "below it")
		fw.eq(x, 0, "x")
		fw.eq(y, -db.Gap, "one gap down")
		fw.eq(bar:GetHeight(), db.StaggerHeight, "its own height")
		fw.eq(FindContainer():GetHeight(), DEFAULT_HEIGHT + db.Gap + db.StaggerHeight, "the container has room for it")
	end)

	fw.it("takes the configured height", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40)

		_G.MiniResourceDisplayDB.StaggerHeight = 14
		context.Addon:Reload()

		fw.eq(FindStaggerBar():GetHeight(), 14, "bar height")
		fw.eq(FindContainer():GetHeight(), DEFAULT_HEIGHT + _G.MiniResourceDisplayDB.Gap + 14, "container height")

		_G.MiniResourceDisplayDB.StaggerHeight = 10
		context.Addon:Reload()
	end)

	fw.it("puts a Mists Brewmaster's chi row under the stagger bar", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40, function()
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_MISTS_CLASSIC
			_G.Enum.PowerType.Chi = 12
		end)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local bar = FindStaggerBar()
		local row

		for _, frame in ipairs(WowMock.Frames) do
			if frame:GetObjectType() == "Frame" and frame:GetParent() == FindContainer() and frame:IsShown() then
				local _, relativeTo = frame:GetPoint(1)

				if relativeTo == bar then
					row = frame
				end
			end
		end

		fw.not_nil(row, "chi row anchored to the stagger bar")
	end)

	fw.it("grows downward when the player changes into Brewmaster", function()
		LoginWithStagger("MONK", WINDWALKER, 40)

		local container = FindContainer()
		local top = TopEdge(container)
		local height = container:GetHeight()

		SetSpec(BREWMASTER)
		WowMock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

		local db = _G.MiniResourceDisplayDB

		fw.truthy(FindStaggerBar():IsShown(), "bar shown")
		fw.eq(container:GetHeight(), height + db.Gap + db.StaggerHeight, "grew by the stagger row")
		fw.eq(TopEdge(container), top, "top edge did not move")
	end)

	fw.it("grows downward when only a stagger change reveals the Brewmaster spec", function()
		LoginWithStagger("MONK", WINDWALKER, 40)

		local container = FindContainer()
		local top = TopEdge(container)
		local height = container:GetHeight()

		SetSpec(BREWMASTER)
		WowMock.FireEvent("UNIT_AURA", "player")

		local db = _G.MiniResourceDisplayDB

		fw.truthy(FindStaggerBar():IsShown(), "bar shown")
		fw.eq(container:GetHeight(), height + db.Gap + db.StaggerHeight, "grew by the stagger row")
		fw.eq(TopEdge(container), top, "top edge did not move")
	end)

	fw.it("moves an old centred Brewmaster position by the height it had before the stagger row", function()
		_G.MiniResourceDisplayDB = {
			Point = "CENTER",
			RelativeTo = "UIParent",
			RelativePoint = "CENTER",
			X = 0,
			Y = -140,
		}

		LoginWithStagger("MONK", BREWMASTER, 40)

		local db = _G.MiniResourceDisplayDB

		fw.truthy(FindStaggerBar():IsShown(), "bar shown")
		fw.eq(db.Point, "TOP", "saved point")
		fw.eq(db.Y, -140 + DEFAULT_HEIGHT / 2, "top edge where the 2.9.0 display had it")
		fw.eq(TopEdge(FindContainer()), -140 + DEFAULT_HEIGHT / 2, "frame top edge")
	end)

	fw.it("puts a dropped Brewmaster frame back on its top edge, stagger row included", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		local db = _G.MiniResourceDisplayDB
		local container = FindContainer()
		local height = container:GetHeight()

		fw.eq(height, DEFAULT_HEIGHT + db.Gap + db.StaggerHeight, "stagger row counted")

		container:ClearAllPoints()
		container:SetPoint("CENTER", _G.UIParent, "CENTER", 40, -60)
		container:GetScript("OnDragStop")(container)

		fw.eq(db.Point, "TOP", "saved point")
		fw.eq(db.Y, -60 + height / 2, "saved y")
		fw.eq(TopEdge(container), -60 + height / 2, "frame did not move")
	end)

	fw.it("shrinks back upward when the option is turned off", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40)

		local container = FindContainer()
		local top = TopEdge(container)

		_G.MiniResourceDisplayDB.ShowStagger = false
		context.Addon:Reload()

		fw.eq(container:GetHeight(), DEFAULT_HEIGHT, "stagger row gone")
		fw.eq(TopEdge(container), top, "top edge did not move")
	end)

	fw.it("builds nothing for another class, even with the Brewmaster spec id", function()
		LoginWithStagger("WARRIOR", BREWMASTER, 40)

		fw.is_nil(FindStaggerBar(), "no stagger bar")
		fw.eq(FindContainer():GetHeight(), DEFAULT_HEIGHT, "no room made for one")
		fw.eq(WowMock.FireEvent("UNIT_AURA", "player"), 0, "no frame listens for UNIT_AURA")
	end)

	fw.it("listens for UNIT_AURA as a monk", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		fw.truthy(WowMock.FireEvent("UNIT_AURA", "player") > 0, "a frame listens for UNIT_AURA")
	end)

	fw.it("gives the pet bar no stagger bar", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		local petContainer = _G["MiniResourceDisplayPetFrame"]

		fw.not_nil(petContainer, "pet container exists")
		fw.is_nil(FindStaggerBar(petContainer), "no stagger bar on the pet")
	end)

	fw.it("stays hidden for a monk in another spec", function()
		LoginWithStagger("MONK", WINDWALKER, 40)

		local bar = FindStaggerBar()

		fw.falsy(bar:IsShown(), "bar hidden")
		fw.eq(bar:GetValue(), 0, "no stagger value pushed")
		fw.eq(FindContainer():GetHeight(), DEFAULT_HEIGHT, "no room made for it")
	end)

	fw.it("hides when the option is off and comes back without a reload", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40)

		_G.UnitStagger = function()
			return 15
		end
		_G.MiniResourceDisplayDB.ShowStagger = false
		context.Addon:Reload()

		local bar = FindStaggerBar()

		fw.falsy(bar:IsShown(), "bar hidden")
		fw.eq(bar:GetValue(), 40, "the new stagger was not pushed")

		_G.MiniResourceDisplayDB.ShowStagger = true
		context.Addon:Reload()

		fw.truthy(bar:IsShown(), "bar shown again")
		fw.eq(bar:GetValue(), 15, "stagger value")
	end)

	fw.it("follows a stagger change that comes with no health change", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		_G.UnitStagger = function()
			return 10
		end
		WowMock.FireEvent("UNIT_AURA", "player")

		fw.eq(FindStaggerBar():GetValue(), 10, "purified stagger")
	end)

	fw.it("takes the default colour on a fresh install", function()
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "MONK" })
		SetSpec(BREWMASTER)
		harness.Login(context)

		local r, g, b = StaggerColor()

		fw.eq(r, 1, "default red")
		fw.eq(g, 0.98, "default green")
		fw.eq(b, 0.72, "default blue")
	end)

	fw.it("takes a changed colour without a reload", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40)

		_G.MiniResourceDisplayDB.StaggerColor = { 0.1, 0.2, 0.3 }
		context.Addon:Reload()

		local r, g, b = StaggerColor()

		fw.eq(r, 0.1, "configured red")
		fw.eq(g, 0.2, "configured green")
		fw.eq(b, 0.3, "configured blue")
	end)

	fw.it("shows the amount as text", function()
		LoginWithStagger("MONK", BREWMASTER, 40)

		local _, text = FindStaggerBar()

		fw.truthy(text:IsShown(), "text shown")
		fw.eq(text:GetText(), "40", "amount")
	end)

	fw.it("shows a percentage of max health, with or without the suffix", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40)

		_G.MiniResourceDisplayDB.UsePercent = true
		context.Addon:Reload()

		local _, text = FindStaggerBar()
		fw.eq(text:GetText(), "20%", "percent of max health")

		_G.MiniResourceDisplayDB.HideTextSuffix = true
		context.Addon:Reload()

		fw.eq(text:GetText(), "20", "no suffix")
	end)

	fw.it("hides the text with the other bars' text", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 40)

		_G.MiniResourceDisplayDB.ShowText = false
		context.Addon:Reload()

		local _, text = FindStaggerBar()
		fw.falsy(text:IsShown(), "text hidden")
	end)

	fw.it("passes a secret stagger straight to the bar and shows the amount", function()
		local context = LoginWithStagger("MONK", BREWMASTER, 10)

		_G.MiniResourceDisplayDB.UsePercent = true
		context.Addon:Reload()

		-- Minted after the load, which installs a fresh mock and forgets earlier secrets.
		local secret = WowMock.MakeSecret(70)
		local secretMax = WowMock.MakeSecret(200)
		_G.UnitStagger = function()
			return secret
		end
		_G.UnitHealthMax = function()
			return secretMax
		end

		-- The client's AbbreviateNumbers takes a secret and hands back a secret string.
		local abbreviate = _G.AbbreviateNumbers
		_G.AbbreviateNumbers = function(value)
			if _G.issecretvalue(value) then
				return WowMock.MakeSecret("70")
			end

			return abbreviate(value)
		end

		local ok, err = pcall(WowMock.FireEvent, "UNIT_AURA", "player")
		_G.AbbreviateNumbers = abbreviate

		fw.truthy(ok, "secret stagger and max health: " .. tostring(err))

		local bar, text = FindStaggerBar()
		local _, max = bar:GetMinMaxValues()

		fw.truthy(rawequal(bar:GetValue(), secret), "secret handed to SetValue")
		fw.truthy(rawequal(max, secretMax), "secret max health handed to SetMinMaxValues")
		fw.truthy(_G.issecretvalue(text:GetText()), "the amount went to the text, not a percentage")
	end)
end)

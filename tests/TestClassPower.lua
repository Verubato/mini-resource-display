-- Drives the class power row through the same events and Reload calls a real client would use,
-- since the boxes it builds are local to MiniResourceDisplay.lua's group closure.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---The player's container frame, the same one TestBarGroup.lua finds bars under.
---@return table?
local function FindContainer()
	return _G["MiniResourceDisplayFrame"]
end

---The row is the container's only Frame child without FontStrings, which tells it apart
---from the text frame.
---@return table?
local function FindClassPowerRow(container)
	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetObjectType() == "Frame" and frame:GetParent() == container then
			local isTextFrame = false

			for _, child in ipairs(WowMock.Frames) do
				if child:GetObjectType() == "FontString" and child:GetParent() == frame then
					isTextFrame = true
					break
				end
			end

			if not isTextFrame then
				return frame
			end
		end
	end
end

---@return table[]
local function FindClassPowerBoxes(row)
	local boxes = {}

	if not row then
		return boxes
	end

	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetObjectType() == "StatusBar" and frame:GetParent() == row then
			boxes[#boxes + 1] = frame
		end
	end

	return boxes
end

---Points GetSpecialization and its C_ replacement at the same fixed spec, the way a real
---character answers both regardless of which one a client happens to expose.
local function SetSpec(specId)
	_G.C_SpecializationInfo.GetSpecialization = function()
		return 1
	end
	_G.C_SpecializationInfo.GetSpecializationInfo = function()
		return specId
	end
end

fw.describe("ClassPower - default", function()
	fw.it("is on for a fresh install, with no saved variable to say otherwise", function()
		-- A brand new install has no saved variable table.
		_G.MiniResourceDisplayDB = nil

		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		fw.eq(_G.MiniResourceDisplayDB.ClassPower.Enabled, true, "class power defaults on")
		fw.truthy(FindClassPowerRow(FindContainer()):IsShown(), "the row shows without turning it on by hand")
	end)

	fw.it("is on for an existing install with no ClassPower key saved yet", function()
		-- An existing user upgrading has other saved settings, but nothing under the
		-- ClassPower key until this version adds it.
		_G.MiniResourceDisplayDB = { Width = 150 }

		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		fw.eq(_G.MiniResourceDisplayDB.ClassPower.Enabled, true, "class power defaults on")
		fw.truthy(FindClassPowerRow(FindContainer()):IsShown(), "the row shows without turning it on by hand")
	end)
end)

fw.describe("ClassPower - power boxes", function()
	fw.it("splits a mainline rogue's combo points into one box per point", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.eq(#boxes, 5, "five boxes for five combo points")

		for i = 1, 3 do
			local min, max = boxes[i]:GetMinMaxValues()
			fw.eq(min, i - 1, "box " .. i .. " min")
			fw.eq(max, i, "box " .. i .. " max")
			fw.eq(boxes[i]:GetValue(), 3, "box " .. i .. " value")
		end

		local min4, max4 = boxes[4]:GetMinMaxValues()
		fw.eq(min4, 3, "box 4 min")
		fw.eq(max4, 4, "box 4 max")
	end)

	fw.it("scales the range by the display mod for fragments", function()
		local context = harness.Load("MiniResourceDisplay", { class = "WARLOCK" })
		_G.UnitPower = function() return 35 end
		_G.UnitPowerMax = function() return 5 end
		_G.UnitPowerDisplayMod = function() return 10 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.eq(#boxes, 5, "five boxes for five soul shards")

		local min4, max4 = boxes[4]:GetMinMaxValues()
		fw.eq(min4, 30, "box 4 min")
		fw.eq(max4, 40, "box 4 max")
		fw.eq(boxes[4]:GetValue(), 35, "box 4 value")
	end)

	fw.it("feeds a secret current value to the bar without touching it", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		local comboPoints = _G.Enum.PowerType.ComboPoints
		local secretCurrent = WowMock.MakeSecret(3)

		-- Only the combo point read is secret here: the main power bar reads its own power
		-- type through the same global, and that one has to stay a plain number.
		_G.UnitPower = function(_, powerType)
			if powerType == comboPoints then
				return secretCurrent
			end
			return 50
		end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true

		local ok = pcall(function()
			context.Addon:Reload()
		end)

		fw.truthy(ok, "no error handling the secret value")

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.truthy(rawequal(boxes[1]:GetValue(), secretCurrent), "the same secret proxy reached the bar")
	end)

	fw.it("collapses to a single box when the max can't be counted", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		local comboPoints = _G.Enum.PowerType.ComboPoints
		local secretMax = WowMock.MakeSecret(5)

		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function(_, powerType)
			if powerType == comboPoints then
				return secretMax
			end
			return 100
		end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.eq(#boxes, 1, "one box when the max is secret")

		local _, max = boxes[1]:GetMinMaxValues()
		fw.truthy(rawequal(max, secretMax), "the box's range tops out at the same secret proxy")
	end)

	fw.it("reads a classic rogue's combo points from the target and refreshes on target change", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		_G.UnitPowerMax = function() return 5 end

		-- Not part of the shared mock, so it has to be stubbed and restored here rather than
		-- relying on WowMock.Install to reset it between tests.
		local originalGetComboPoints = _G.GetComboPoints
		local points = 2
		_G.GetComboPoints = function()
			return points
		end

		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.eq(boxes[1]:GetValue(), 2, "reads combo points from GetComboPoints")

		points = 4
		WowMock.FireEvent("PLAYER_TARGET_CHANGED")

		fw.eq(boxes[1]:GetValue(), 4, "refreshes after a target change")

		_G.GetComboPoints = originalGetComboPoints
	end)

	fw.it("changes the box count when UNIT_MAXPOWER reports a new max", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		local max = 3
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return max end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.eq(#FindClassPowerBoxes(row), 3, "three boxes for a max of three")

		max = 5
		WowMock.FireEvent("UNIT_MAXPOWER", "player")

		fw.eq(#FindClassPowerBoxes(row), 5, "five boxes once the max grows")
	end)
end)

fw.describe("ClassPower - layout", function()
	fw.it("grows the container when the row shows and shrinks back when disabled", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		-- Saved variables survive a fresh login in the mock, the way they would across a real
		-- reload, so a prior test's Enabled can't be assumed false here.
		_G.MiniResourceDisplayDB.ClassPower.Enabled = false
		context.Addon:Reload()

		local container = FindContainer()
		local _, baseHeight = container:GetSize()

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local _, grownHeight = container:GetSize()
		local gap = _G.MiniResourceDisplayDB.Gap or 0
		local cpHeight = _G.MiniResourceDisplayDB.ClassPower.Height

		fw.eq(grownHeight - baseHeight, gap + cpHeight, "grew by the gap plus the class power height")

		_G.MiniResourceDisplayDB.ClassPower.Enabled = false
		context.Addon:Reload()

		local _, shrunkHeight = container:GetSize()
		fw.eq(shrunkHeight, baseHeight, "back to the original height once disabled")
	end)

	fw.it("stays hidden after a faded-out combat exit when a power event resizes the row", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		WowMock.State.InCombat = false
		WowMock.FireEvent("PLAYER_REGEN_ENABLED")

		local container = FindContainer()

		-- Simulate the fade out actually finishing, the way OnFinished would leave it.
		container.FadeOut:GetScript("OnFinished")()

		fw.falsy(container:IsShown(), "hidden once the fade out completes")

		-- None of these change what's shown.
		WowMock.FireEvent("UNIT_MAXPOWER", "player")
		fw.falsy(container:IsShown(), "still hidden after UNIT_MAXPOWER")

		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")
		fw.falsy(container:IsShown(), "still hidden after UNIT_DISPLAYPOWER")

		WowMock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
		fw.falsy(container:IsShown(), "still hidden after PLAYER_SPECIALIZATION_CHANGED")
	end)

	fw.it("shows the container when class power becomes the only row while already in combat", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DRUID" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		_G.UnitPowerType = function() return 0, "MANA" end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ShowHealth = false
		_G.MiniResourceDisplayDB.ShowPower = false
		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local container = FindContainer()

		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		fw.falsy(container.FadeIn:IsPlaying(), "no row yet, so combat alone shows nothing")

		_G.UnitPowerType = function() return 3, "ENERGY" end
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.truthy(container.FadeIn:IsPlaying(), "class power appearing as the only row shows the container mid-combat")
	end)

	fw.it("hides the container when class power stops being the only row, still in combat", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DRUID" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		_G.UnitPowerType = function() return 3, "ENERGY" end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ShowHealth = false
		_G.MiniResourceDisplayDB.ShowPower = false
		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local container = FindContainer()

		WowMock.State.InCombat = true
		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		fw.truthy(container.FadeIn:IsPlaying(), "class power alone shows the container in combat")

		-- Simulate the fade in actually finishing, the way OnPlay would leave it.
		container.FadeIn:GetScript("OnPlay")()
		fw.truthy(container:IsShown(), "shown once the fade in starts playing")

		_G.UnitPowerType = function() return 0, "MANA" end
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		-- rowsEmpty hides the container directly rather than fading it out.
		fw.falsy(container:IsShown(), "leaving the energy form empties the rows and hides the container mid-combat")
	end)

	fw.it("does not re-anchor the boxes when a second power event reports the same count", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.eq(#boxes, 5, "five boxes for five combo points")

		local anchorCalls = 0
		local originalClearAllPoints = boxes[1].ClearAllPoints
		boxes[1].ClearAllPoints = function(...)
			anchorCalls = anchorCalls + 1
			return originalClearAllPoints(...)
		end

		WowMock.FireEvent("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")

		fw.eq(anchorCalls, 0, "layout is skipped when the box count hasn't changed")

		boxes[1].ClearAllPoints = originalClearAllPoints
	end)
end)

fw.describe("ClassPower - filters", function()
	fw.it("shows a druid only with energy as the display power", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DRUID" })
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return 5 end
		_G.UnitPowerType = function() return 0, "MANA" end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.falsy(row:IsShown(), "no row while the display power is mana")

		_G.UnitPowerType = function() return 3, "ENERGY" end
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.truthy(row:IsShown(), "row appears once the player is in an energy form")
		fw.eq(#FindClassPowerBoxes(row), 5, "five boxes for five combo points")
	end)

	fw.it("shows a mage on the arcane charge spec and not on the other", function()
		local context = harness.Load("MiniResourceDisplay", { class = "MAGE" })
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return 4 end
		SetSpec(62)
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.truthy(row:IsShown(), "arcane charge spec shows the row")

		SetSpec(63)
		WowMock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

		fw.falsy(row:IsShown(), "the other spec hides it")
	end)

	fw.it("does not show a monk on the wrong spec", function()
		local context = harness.Load("MiniResourceDisplay", { class = "MONK" })
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return 5 end
		SetSpec(268)
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		fw.falsy(FindClassPowerRow(FindContainer()):IsShown(), "monk on the wrong spec gets no row")
	end)

	fw.it("gets no row and no error when the enum is missing the field it needs", function()
		local context = harness.Load("MiniResourceDisplay", { class = "PALADIN" })
		_G.Enum.PowerType = { Mana = 0 }
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return 5 end

		local ok = pcall(function()
			harness.Login(context)
			_G.MiniResourceDisplayDB.ClassPower.Enabled = true
			context.Addon:Reload()
		end)

		fw.truthy(ok, "no error from a missing enum field")
		fw.falsy(FindClassPowerRow(FindContainer()):IsShown(), "no row without the enum entry")
	end)

	fw.it("gets no row for a paladin whose holy power doesn't exist on this client", function()
		local context = harness.Load("MiniResourceDisplay", { class = "PALADIN" })
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		_G.UnitPower = function() return 2 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.truthy(row:IsShown(), "shown while holy power has a max on this client")

		_G.UnitPower = function() return 0 end
		_G.UnitPowerMax = function() return 0 end
		WowMock.FireEvent("UNIT_MAXPOWER", "player")

		fw.falsy(row:IsShown(), "no holy power on this client")
	end)

	fw.it("keys a classic rogue's row on the class token rather than a spec id", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.truthy(row:IsShown(), "shown by default with Show.ROGUE true")

		_G.MiniResourceDisplayDB.ClassPower.Show.ROGUE = false
		context.Addon:Reload()

		fw.falsy(row:IsShown(), "the classic key is the class token")

		_G.MiniResourceDisplayDB.ClassPower.Show.ROGUE = true
	end)
end)

fw.describe("ClassPower - per-spec visibility", function()
	fw.it("hides for a toggled-off spec and shows again after switching spec", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		SetSpec(260)
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		_G.MiniResourceDisplayDB.ClassPower.Show[260] = false
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.falsy(row:IsShown(), "hidden while the current spec is toggled off")

		SetSpec(261)
		WowMock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

		fw.truthy(row:IsShown(), "shown again after switching to a spec with no override")

		_G.MiniResourceDisplayDB.ClassPower.Show[260] = true
	end)
end)

fw.describe("ClassPower - runes", function()
	fw.it("reads six wrath runes, tracks a recharging one, and stops polling once all are ready", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DEATHKNIGHT" })
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_WRATH_CLASSIC

		local runes = {}
		for i = 1, 6 do
			runes[i] = { ready = true, runeType = 1 }
		end
		runes[6] = { ready = false, start = _G.GetTime(), duration = 10, runeType = 4 }

		_G.GetRuneCooldown = function(index)
			local rune = runes[index]
			return rune.start or 0, rune.duration or 0, rune.ready
		end
		_G.GetRuneType = function(index)
			return runes[index].runeType
		end

		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		local boxes = FindClassPowerBoxes(row)
		fw.eq(#boxes, 6, "six rune boxes")

		for i = 1, 5 do
			local min, max = boxes[i]:GetMinMaxValues()
			fw.eq(min, 0, "ready rune " .. i .. " min")
			fw.eq(max, 1, "ready rune " .. i .. " max")
			fw.eq(boxes[i]:GetValue(), 1, "ready rune " .. i .. " full")
		end

		local _, maxRecharging = boxes[6]:GetMinMaxValues()
		fw.eq(maxRecharging, 10, "recharging rune's range is its full duration")
		fw.eq(boxes[6]:GetValue(), 0, "recharging rune starts at no progress")
		fw.not_nil(row:GetScript("OnUpdate"), "polling while a rune is still recharging")

		WowMock.AdvanceTime(4)
		WowMock.RunOnUpdate(4)

		fw.eq(boxes[6]:GetValue(), 4, "recharging rune reads elapsed time after a tick")

		runes[6].ready = true
		WowMock.AdvanceTime(6)
		WowMock.RunOnUpdate(6)

		fw.is_nil(row:GetScript("OnUpdate"), "polling stops once every rune is ready")

		local r, g, b = boxes[1]:GetStatusBarColor()
		fw.eq(r, 0.77, "blood rune red")
		fw.eq(g, 0.12, "blood rune green")
		fw.eq(b, 0.23, "blood rune blue")
	end)

	fw.it("clears the OnUpdate poll when class power is disabled while a rune is recharging", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DEATHKNIGHT" })
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_WRATH_CLASSIC

		local runes = {}
		for i = 1, 6 do
			runes[i] = { ready = true, runeType = 1 }
		end
		runes[6] = { ready = false, start = _G.GetTime(), duration = 10, runeType = 4 }

		_G.GetRuneCooldown = function(index)
			local rune = runes[index]
			return rune.start or 0, rune.duration or 0, rune.ready
		end
		_G.GetRuneType = function(index)
			return runes[index].runeType
		end

		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		fw.not_nil(row:GetScript("OnUpdate"), "polling while a rune is recharging")

		_G.MiniResourceDisplayDB.ClassPower.Enabled = false
		context.Addon:Reload()

		fw.is_nil(row:GetScript("OnUpdate"), "polling stops once class power is turned off")
	end)

	fw.it("throttles the rune refresh to the poll interval", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DEATHKNIGHT" })
		_G.WOW_PROJECT_ID = _G.WOW_PROJECT_WRATH_CLASSIC

		local runes = {}
		for i = 1, 6 do
			runes[i] = { ready = true, runeType = 1 }
		end
		runes[6] = { ready = false, start = _G.GetTime(), duration = 10, runeType = 4 }

		_G.GetRuneCooldown = function(index)
			local rune = runes[index]
			return rune.start or 0, rune.duration or 0, rune.ready
		end
		_G.GetRuneType = function(index)
			return runes[index].runeType
		end

		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		fw.eq(boxes[6]:GetValue(), 0, "recharging rune starts at no progress")

		-- 0.0625 is exact in binary, so the accumulated elapsed below is exact too.
		WowMock.AdvanceTime(0.0625)
		WowMock.RunOnUpdate(0.0625)

		fw.eq(boxes[6]:GetValue(), 0, "no refresh below the throttle interval")

		WowMock.AdvanceTime(0.0625)
		WowMock.RunOnUpdate(0.0625)

		fw.eq(boxes[6]:GetValue(), 0.125, "refreshes once the accumulated elapsed passes the throttle interval")
	end)
end)

fw.describe("ClassPower - colours", function()
	fw.it("colours a power box with the player's class colour", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		local classColor = _G.RAID_CLASS_COLORS.ROGUE
		local r, g, b = boxes[1]:GetStatusBarColor()

		fw.eq(r, classColor.r, "power box red matches the rogue's class colour")
		fw.eq(g, classColor.g, "power box green matches the rogue's class colour")
		fw.eq(b, classColor.b, "power box blue matches the rogue's class colour")
	end)

	fw.it("falls back to PowerBarColor when the class has no class colour", function()
		local context = harness.Load("MiniResourceDisplay", { class = "ROGUE" })
		_G.UnitPower = function() return 3 end
		_G.UnitPowerMax = function() return 5 end
		harness.Login(context)

		_G.RAID_CLASS_COLORS.ROGUE = nil
		_G.PowerBarColor.COMBO_POINTS = { r = 0.4, g = 0.5, b = 0.6 }

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		local r, g, b = boxes[1]:GetStatusBarColor()

		fw.eq(r, 0.4, "falls back to PowerBarColor red with no class colour")
		fw.eq(g, 0.5, "falls back to PowerBarColor green with no class colour")
		fw.eq(b, 0.6, "falls back to PowerBarColor blue with no class colour")
	end)

	fw.it("colours retail runes by the Blood, Frost and Unholy spec trees", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DEATHKNIGHT" })

		_G.GetRuneCooldown = function()
			return 0, 0, true
		end
		_G.GetRuneType = function()
			return nil
		end

		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true

		local specs = { [250] = { 0.77, 0.12, 0.23 }, [251] = { 0.10, 0.70, 0.90 }, [252] = { 0.20, 0.80, 0.20 } }

		for specId, rgb in pairs(specs) do
			SetSpec(specId)
			context.Addon:Reload()

			local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
			local r, g, b = boxes[1]:GetStatusBarColor()

			fw.eq(r, rgb[1], "spec " .. specId .. " rune red")
			fw.eq(g, rgb[2], "spec " .. specId .. " rune green")
			fw.eq(b, rgb[3], "spec " .. specId .. " rune blue")
		end
	end)

	fw.it("recolours retail runes when PLAYER_SPECIALIZATION_CHANGED fires", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DEATHKNIGHT" })

		_G.GetRuneCooldown = function()
			return 0, 0, true
		end
		_G.GetRuneType = function()
			return nil
		end

		SetSpec(250)
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		SetSpec(251)
		WowMock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

		local boxes = FindClassPowerBoxes(FindClassPowerRow(FindContainer()))
		local frost = { 0.10, 0.70, 0.90 }
		local r, g, b = boxes[1]:GetStatusBarColor()

		fw.eq(r, frost[1], "rune red follows the new spec after the event")
		fw.eq(g, frost[2], "rune green follows the new spec after the event")
		fw.eq(b, frost[3], "rune blue follows the new spec after the event")
	end)

	fw.it("falls back to the class colour for retail runes with no spec chosen", function()
		local context = harness.Load("MiniResourceDisplay", { class = "DEATHKNIGHT" })

		local runes = {}
		for i = 1, 6 do
			runes[i] = { ready = true }
		end
		runes[6] = { ready = false, start = _G.GetTime(), duration = 10 }

		_G.GetRuneCooldown = function(index)
			local rune = runes[index]
			return rune.start or 0, rune.duration or 0, rune.ready
		end
		_G.GetRuneType = function()
			return nil
		end

		SetSpec(250)
		harness.Login(context)

		_G.MiniResourceDisplayDB.ClassPower.Enabled = true
		context.Addon:Reload()

		local row = FindClassPowerRow(FindContainer())
		local boxes = FindClassPowerBoxes(row)
		fw.not_nil(row:GetScript("OnUpdate"), "polling while a rune is recharging")

		-- A respec can leave the spec unknown until the next full refresh.
		_G.C_SpecializationInfo.GetSpecialization = function()
			return nil
		end

		WowMock.AdvanceTime(4)
		WowMock.RunOnUpdate(4)

		local classColor = _G.RAID_CLASS_COLORS.DEATHKNIGHT
		local r, g, b = boxes[6]:GetStatusBarColor()

		fw.eq(r, classColor.r, "rune red falls back to the class colour")
		fw.eq(g, classColor.g, "rune green falls back to the class colour")
		fw.eq(b, classColor.b, "rune blue falls back to the class colour")
	end)
end)

fw.describe("ClassPower - config panel", function()
	---Wraps a framework function so every call is recorded, matching the pattern
	---TestConfig.lua uses to reach the panel's own local controls.
	local function Spy(framework, name)
		local calls = {}
		local original = framework[name]

		framework[name] = function(self, options)
			calls[#calls + 1] = options
			return original(self, options)
		end

		return calls
	end

	local function FindHeader(calls, title)
		for _, options in ipairs(calls) do
			if options.Title == title then
				return options
			end
		end
	end

	fw.it("makes one checkbox per visibility entry, and a reset shows a hidden one again", function()
		local context = harness.Load("MiniResourceDisplay", { class = "MAGE" })
		local framework = context.Addon.Framework
		local panelHeaderCalls = Spy(framework, "PanelHeader")
		local checkboxCalls = Spy(framework, "Checkbox")

		-- Real mage spec ids, so only Arcane matches the arcane charge candidate's SpecId
		-- rather than the mock's default fake ones matching nothing.
		_G.GetSpecializationInfoForClassID = function(_, index)
			local specs = { 62, 63, 64 }
			return specs[index], "Spec", "A spec", 134400, "DAMAGER"
		end

		harness.Login(context)

		local cpHeader = FindHeader(panelHeaderCalls, "Class Power")
		fw.not_nil(cpHeader, "Class Power PanelHeader call")

		local entryChecks = {}
		for _, options in ipairs(checkboxCalls) do
			if options.Parent == cpHeader.Parent and options.LabelText ~= "Show class power" then
				entryChecks[#entryChecks + 1] = options
			end
		end

		fw.eq(#entryChecks, 1, "one checkbox, for the mage's only arcane charge candidate")

		local first = entryChecks[1]
		first.SetValue(false)
		fw.falsy(first.GetValue(), "checkbox reflects the toggle")

		local mainHeader = FindHeader(panelHeaderCalls, nil)
		mainHeader.Reset.OnAccept()

		fw.truthy(first.GetValue(), "reset brings the entry back to shown")
	end)
end)

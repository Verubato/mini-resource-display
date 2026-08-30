-- Exercises how Config.lua wires the settings panel to the framework: the Shield tab's
-- divider, the Misc tab's control order, and the reset button. Spies patched onto
-- addon.Framework before login capture what Config.lua passes the framework, since the
-- panel's own controls are local to Config:Init and not otherwise reachable from a test.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---Wraps a framework function so every call is recorded, in the single shared order list,
---before running the real one. A per-kind list alone can't prove one call came before
---another made through a different function.
---@param framework table
---@param name string
---@param order table[] shared across every spied function
---@return table[] calls this function's own calls, in the same relative order
local function Spy(framework, name, order)
	local calls = {}
	local original = framework[name]

	framework[name] = function(self, options)
		calls[#calls + 1] = options
		order[#order + 1] = { Kind = name, Options = options }
		return original(self, options)
	end

	return calls
end

---Loads the addon, spies on the GUI calls Config.lua and PanelHeader make, then logs in so
---Config:Init runs with the spies already in place.
local function BuildContext()
	local context = harness.Load("MiniResourceDisplay")
	local framework = context.Addon.Framework
	local order = {}

	local spies = {
		Order = order,
		PanelHeader = Spy(framework, "PanelHeader", order),
		Divider = Spy(framework, "Divider", order),
		Checkbox = Spy(framework, "Checkbox", order),
		Slider = Spy(framework, "Slider", order),
		Button = Spy(framework, "Button", order),
	}

	harness.Login(context)

	return context, spies
end

---The player's health bar is the first StatusBar this display parents to its container.
---@return table?
local function FindHealthBar()
	local container = _G["MiniResourceDisplayFrame"]

	if not container then
		return nil
	end

	for _, frame in ipairs(WowMock.Frames) do
		if frame:GetObjectType() == "StatusBar" and frame:GetParent() == container then
			return frame
		end
	end
end

---Finds the single PanelHeader call for the given title, nil for the main panel's own header.
local function FindHeader(calls, title)
	for _, options in ipairs(calls) do
		if options.Title == title then
			return options
		end
	end

	return nil
end

---The Texture control is the panel's only modern dropdown, so its menu generator is the one
---frame in WowMock.Frames that carries one.
---@return table?
local function FindTextureDropdown()
	for _, frame in ipairs(WowMock.Frames) do
		if frame.__menuGenerator then
			return frame
		end
	end
end

---The shared mock's own menu description has no AddInitializer, so calling a decorator
---directly would stay green even if it were never wired to the dropdown.
---@param dd table
---@return table<any, fun(button: table)>
local function MenuInitializers(dd)
	local initializers = {}
	local description = {}

	setmetatable(description, {
		__index = function()
			return function() end
		end,
	})

	description.CreateRadio = function(_, _, _, _, value)
		local node = {}

		node.AddInitializer = function(_, initializer)
			initializers[value] = initializer
		end

		return node
	end

	dd.__menuGenerator(dd, description)

	return initializers
end

---A stand-in for the texture region a real preview would create on a menu row.
---@return table
local function NewPreviewTexture()
	local texture = {}

	function texture:ClearAllPoints()
		texture.points = {}
	end

	function texture:SetPoint(point, _, relativePoint, x, y)
		texture.points = texture.points or {}
		texture.points[#texture.points + 1] = { Point = point, RelativePoint = relativePoint, X = x, Y = y }
	end

	function texture:SetSize(width, height)
		texture.width = width
		texture.height = height
	end

	function texture:SetTexture(file)
		texture.file = file
	end

	function texture:Show()
		texture.shown = true
	end

	function texture:Hide()
		texture.shown = false
	end

	return texture
end

---A stand-in for a pooled menu row, which a real menu creates once and reuses after that.
---@param height number
---@return table
local function StubPreviewButton(height)
	local button = { CreateTextureCalls = 0 }

	function button:CreateTexture()
		button.CreateTextureCalls = button.CreateTextureCalls + 1
		return NewPreviewTexture()
	end

	function button:GetHeight()
		return height
	end

	return button
end

fw.describe("Config panel: Shield tab", function()
	fw.it("labels the header's own divider Settings", function()
		local _, spies = BuildContext()
		local shieldHeader = FindHeader(spies.PanelHeader, "Shield")

		fw.not_nil(shieldHeader, "Shield PanelHeader call")
		fw.eq(shieldHeader.Divider, "Settings", "Shield divider label")
	end)

	fw.it("no longer draws its own separate Colour & Opacity divider", function()
		local _, spies = BuildContext()

		for _, options in ipairs(spies.Divider) do
			fw.neq(options.Text, "Colour & Opacity", "stray Shield divider")
		end
	end)
end)

fw.describe("Config panel: Misc tab", function()
	fw.it("creates the hide text suffix checkbox before the opacity slider", function()
		local _, spies = BuildContext()
		local miscHeader = FindHeader(spies.PanelHeader, "Misc")
		local checkboxIndex, sliderIndex

		for i, entry in ipairs(spies.Order) do
			if entry.Options.Parent == miscHeader.Parent then
				if entry.Kind == "Checkbox" and entry.Options.LabelText == "Hide text suffix" then
					checkboxIndex = i
				elseif entry.Kind == "Slider" then
					sliderIndex = i
				end
			end
		end

		fw.not_nil(checkboxIndex, "hide text suffix checkbox")
		fw.not_nil(sliderIndex, "out of combat opacity slider")
		fw.truthy(checkboxIndex < sliderIndex, "checkbox created before the slider")
	end)
end)

fw.describe("Config panel: reset to defaults", function()
	fw.it("puts the reset button on the main header instead of a hand-rolled one", function()
		local context, spies = BuildContext()
		local mainHeader = FindHeader(spies.PanelHeader, nil)

		fw.not_nil(mainHeader, "main PanelHeader call")
		fw.not_nil(mainHeader.Reset, "Reset option")
		fw.eq(type(mainHeader.Reset.OnAccept), "function", "Reset.OnAccept")

		for _, options in ipairs(spies.Button) do
			fw.neq(options.Text, "Reset to defaults", "hand-rolled reset button")
		end

		fw.is_nil(_G.StaticPopupDialogs[context.Name:upper() .. "_RESET_DEFAULTS"], "hand-rolled confirm popup")
	end)

	fw.it("resets saved settings back to their defaults when accepted", function()
		local _, spies = BuildContext()
		local mainHeader = FindHeader(spies.PanelHeader, nil)

		_G.MiniResourceDisplayDB.HideTextSuffix = true

		mainHeader.Reset.OnAccept()

		fw.eq(_G.MiniResourceDisplayDB.HideTextSuffix, false, "HideTextSuffix back to default")
	end)
end)

fw.describe("Texture media subscription", function()
	fw.it("coalesces registrations and reaches the live health bar once a texture arrives late", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local healthBar = FindHealthBar()

		fw.not_nil(healthBar, "the player's health bar exists")

		local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
		fw.not_nil(lsm, "LibSharedMedia resolves under the mock")

		lsm:Register("statusbar", "MiniResourceDisplay Coalesce One", "Interface\\AddOns\\Test\\CoalesceOne.tga")
		lsm:Register("statusbar", "MiniResourceDisplay Coalesce Two", "Interface\\AddOns\\Test\\CoalesceTwo.tga")

		fw.eq(WowMock.RunTimers(), 1, "two registrations in one frame coalesce into a single refresh")

		local textureName = "MiniResourceDisplay Late Texture"
		local texturePath = "Interface\\AddOns\\MiniResourceDisplay\\LateTexture.tga"

		-- Before the name is registered, Fetch answers LibSharedMedia's own default statusbar
		-- rather than nil, which is what the bar draws until the name resolves to something else.
		local fallbackTexture = lsm:Fetch("statusbar", textureName)
		fw.not_nil(fallbackTexture, "LibSharedMedia has a default statusbar to fall back on")

		local previousTexture = _G.MiniResourceDisplayDB.Texture

		-- Mirrors a name saved from a previous session, before this session's texture pack
		-- has registered it.
		_G.MiniResourceDisplayDB.Texture = textureName
		context.Addon:Reload()

		local beforeRegister = healthBar:GetStatusBarTexture()
		fw.eq(beforeRegister and beforeRegister:GetTexture(), fallbackTexture, "the bar starts on the default texture")

		lsm:Register("statusbar", textureName, texturePath)

		local afterRegister = healthBar:GetStatusBarTexture()
		fw.eq(
			afterRegister and afterRegister:GetTexture(),
			fallbackTexture,
			"the registration alone doesn't reach the live bar yet"
		)

		WowMock.RunTimers()

		local afterRefresh = healthBar:GetStatusBarTexture()
		fw.eq(
			afterRefresh and afterRefresh:GetTexture(),
			texturePath,
			"the live bar picks up the texture once the coalesced refresh runs"
		)

		_G.MiniResourceDisplayDB.Texture = previousTexture
	end)
end)

fw.describe("Texture dropdown preview", function()
	fw.it("previews the file a row names rather than the live global override", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
		fw.not_nil(lsm, "LibSharedMedia resolves under the mock")

		local overrideName = "MiniResourceDisplay Preview Override"
		local rowName = "MiniResourceDisplay Preview Row"
		local rowPath = "Interface\\AddOns\\Test\\PreviewRow.tga"

		lsm:Register("statusbar", overrideName, "Interface\\AddOns\\Test\\PreviewOverride.tga")
		lsm:Register("statusbar", rowName, rowPath)
		lsm:SetGlobal("statusbar", overrideName)

		local textureDdl = FindTextureDropdown()
		fw.not_nil(textureDdl, "the texture dropdown wires a menu generator")

		local rowInitializer = MenuInitializers(textureDdl)[rowName]
		fw.not_nil(rowInitializer, "the texture dropdown wires a row initializer for the registered name")

		local button = StubPreviewButton(20)
		rowInitializer(button)

		local preview = button.MiniResourceDisplayPreview
		fw.not_nil(preview, "the row creates a preview texture")
		fw.eq(preview.file, rowPath, "the row previews the file it names rather than the global override")
		fw.truthy(preview.shown, "the preview is shown")
	end)

	fw.it("reuses one texture across rows instead of creating a new one per open", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
		local firstName = "MiniResourceDisplay Preview First"
		local secondName = "MiniResourceDisplay Preview Second"
		local firstPath = "Interface\\AddOns\\Test\\PreviewFirst.tga"
		local secondPath = "Interface\\AddOns\\Test\\PreviewSecond.tga"

		lsm:Register("statusbar", firstName, firstPath)
		lsm:Register("statusbar", secondName, secondPath)

		local initializers = MenuInitializers(FindTextureDropdown())
		local button = StubPreviewButton(20)

		initializers[firstName](button)
		local preview = button.MiniResourceDisplayPreview
		fw.eq(preview.file, firstPath, "the first row previews its own file")
		fw.eq(button.CreateTextureCalls, 1, "the row creates its preview texture once")

		initializers[secondName](button)
		fw.eq(button.MiniResourceDisplayPreview, preview, "a reopened row keeps the texture it first created")
		fw.eq(button.CreateTextureCalls, 1, "a reopened row doesn't create a second texture")
		fw.eq(preview.file, secondPath, "the reused texture is repointed at the reopened row's own file")

		fw.eq(#preview.points, 1, "the reused texture drops the anchor the earlier row gave it")
		fw.eq(preview.points[1].Point, "RIGHT", "the preview hangs off the row's right edge")
		fw.eq(preview.points[1].RelativePoint, "RIGHT", "anchored to that same edge of the row")
	end)

	fw.it("previews the built-in bar for the Blizzard row", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local initializers = MenuInitializers(FindTextureDropdown())
		local blizzardInitializer = initializers["Blizzard"]
		fw.not_nil(blizzardInitializer, "the Blizzard row wires an initializer")

		local button = StubPreviewButton(20)
		blizzardInitializer(button)

		fw.eq(
			button.MiniResourceDisplayPreview.file,
			"Interface\\TARGETINGFRAME\\UI-StatusBar",
			"the Blizzard row previews the built-in statusbar texture"
		)
	end)

	fw.it("sizes the preview inside the row's own height, not flush with its edges", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local initializers = MenuInitializers(FindTextureDropdown())
		local button = StubPreviewButton(20)

		initializers["Blizzard"](button)

		local preview = button.MiniResourceDisplayPreview
		fw.truthy(preview.height > 0 and preview.height < 20, "the preview height is inset from the row's own height")
		fw.truthy(preview.width > 0, "the preview has a visible width")
	end)
end)

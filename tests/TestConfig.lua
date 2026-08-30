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

---Every row's label, keyed by the value it sets. A label carries its own texture escape, so
---this is where the swatch shows up rather than on any region.
---@param dd table
---@return table<any, string>
local function MenuLabels(dd)
	local labels = {}
	local description = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})

	description.CreateRadio = function(_, label, _, _, value)
		labels[value] = label
	end

	dd.__menuGenerator(dd, description)

	return labels
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
	fw.it("draws the file a row names rather than the live global override", function()
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

		local label = MenuLabels(textureDdl)[rowName]

		fw.not_nil(label, "the registered face has a row")
		fw.truthy(label:find(rowPath, 1, true), "the row draws the file it names rather than the global override")
		fw.truthy(label:find(rowName, 1, true), "the row still reads as its own name")
	end)

	fw.it("carries a texture escape sized to draw something", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local label = MenuLabels(FindTextureDropdown())["Blizzard"]
		local height, width = label:match("|T.-:(%d+):(%d+)|t")

		fw.not_nil(height, "the row opens with a texture escape")
		fw.truthy(tonumber(width) > 0, "the swatch has a visible width")
		fw.truthy(tonumber(height) > 0, "the swatch has a visible height")
	end)

	fw.it("draws the built-in bar for the Blizzard row", function()
		local context = harness.Load("MiniResourceDisplay")
		harness.Login(context)

		local label = MenuLabels(FindTextureDropdown())["Blizzard"]

		fw.truthy(
			label:find(context.Addon.BlizzardStatusBarTexture, 1, true),
			"the Blizzard row draws the built-in statusbar texture"
		)
	end)
end)

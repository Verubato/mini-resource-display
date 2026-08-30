-- Exercises how Config.lua wires the settings panel to the framework: the Shield tab's
-- divider, the Misc tab's control order, and the reset button. Spies patched onto
-- addon.Framework before login capture what Config.lua passes the framework, since the
-- panel's own controls are local to Config:Init and not otherwise reachable from a test.

local fw = require("TestFramework")
local harness = require("AddonHarness")

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

---Finds the single PanelHeader call for the given title, nil for the main panel's own header.
local function FindHeader(calls, title)
	for _, options in ipairs(calls) do
		if options.Title == title then
			return options
		end
	end

	return nil
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

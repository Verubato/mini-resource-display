local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
---@type MiniFramework
local mini = addon.Framework
---@type Db
local db
---@class Db
local dbDefaults = {
	Point = "CENTER",
	RelativeTo = "UIParent",
	RelativePoint = "CENTER",
	X = 0,
	Y = -140,

	Locked = false,

	Width = 150,
	Height = 15,

	Gap = 0,
	Padding = 2,

	ShowHealth = true,
	ShowPower = true,
	UseClassColorHealth = false,

	ShowText = true,
	Font = "Fonts\\FRIZQT__.TTF",
	FontSize = 11,
	FontFlags = "OUTLINE",
	FontShadow = true,

	-- A LibSharedMedia name, not a texture path: the dropdown lists names, and anything else
	-- has no entry to match so it shows the raw value instead.
	Texture = "Blizzard",
	Border = true,

	HealthColor = { 0, 1, 0 },
	PowerColor = { 0.2, 0.6, 1.0 },
	PowerUseTypeColor = true,

	AlwaysShow = false,
	OutOfCombatOpacity = 1,
	HideTextSuffix = false,

	UsePercent = false,

	FadeInDuration = 1,
	FadeOutDuration = 1,

	HealthTextFormat = "%s/%s",
	PowerTextFormat = "%s/%s",

	ShowPetBar = false,
	PetWidth = 150,
	PetHeight = 15,

	Shield = {
		Enabled = true,
		Color = { 1, 1, 1 },
		Opacity = 1,
	},

	IncomingHealColor = { 0, 1, 0 },

	-- Classic-only; ignored and never shown in the options on retail, where power regen
	-- is continuous rather than ticked.
	Ticker = {
		-- On by default. Harmless left true on retail, where IsSupported gates the whole
		-- feature out before anything reads this.
		Enabled = true,
		Color = { 1, 1, 1 },
		-- Fully opaque by default. Anything less blends with whatever the marker happens to be
		-- crossing, so it looks like it changes colour partway along the bar.
		Opacity = 1,
		Thickness = 2,
	},

	Pet = {
		Point = "CENTER",
		RelativeTo = "UIParent",
		RelativePoint = "CENTER",
		X = 0,
		Y = -165,
		Locked = false,
	},
}
---@class Config
local M = {}

addon.Config = M

local function GetTexturesList()
	if not LSM then
		return { "Blizzard" }
	end

	local list = LSM:List("statusbar")
	table.sort(list)
	return list
end

function M:Init()
	-- A styled button clashes with the stock Blizzard art around it in the settings screen.
	mini:SetCustomStyling(true, { Button = false })

	db = mini:GetSavedVars(dbDefaults)

	-- Migrate renamed db key: Overshield -> Shield
	if db.Overshield then
		db.Shield = db.Overshield
		db.Overshield = nil
	end

	-- Migrate the old texture default, which stored a path where a LibSharedMedia name belongs.
	-- Only ever reachable as the default, since the dropdown offers names alone.
	if db.Texture == "Interface\\TARGETINGFRAME\\UI-StatusBar" then
		db.Texture = "Blizzard"
	end

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	-- Every panel is collected so a reset refreshes them all, not just whichever one happens
	-- to be open; the rest would otherwise keep showing the old values until their next OnShow.
	local panels = { panel }

	local function ResetToDefaults()
		db = mini:ResetSavedVars(dbDefaults)

		for _, p in ipairs(panels) do
			if p.MiniRefresh then
				p:MiniRefresh()
			end
		end

		addon:Reload()
	end

	-- Addon scoped so sibling Mini addons can't collide on the key.
	local resetPopup = addonName:upper() .. "_RESET_DEFAULTS"

	StaticPopupDialogs[resetPopup] = {
		text = "Reset all " .. addonName .. " settings back to their defaults?",
		button1 = YES,
		button2 = NO,
		OnAccept = ResetToDefaults,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		-- Keeps the popup off the stock frames Blizzard reuses, which can arrive tainted.
		preferredIndex = 3,
	}

	local verticalSpacing = mini.VerticalSpacing
	local horizontalSpacing = mini.HorizontalSpacing
	local columns = 4
	local columnStep = mini:ColumnWidth(columns, mini.HorizontalSpacing, 0)
	local header = mini:PanelHeader({
		Parent = panel,
		Description = "Shows simple personal resource style health and power bars.",
		Gap = 6,
	})

	local resetButton = mini:Button({
		Parent = panel,
		Text = "Reset to defaults",
		Width = 140,
		OnClick = function()
			StaticPopup_Show(resetPopup)
		end,
	})

	-- Level with the header title, inset to the same right edge the dividers use.
	resetButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -horizontalSpacing, -verticalSpacing)

	local mainDivider = mini:Divider({
		Parent = panel,
		Text = "Settings",
	})

	mainDivider:SetPoint("TOP", header.Anchor, "BOTTOM", 0, -verticalSpacing)
	mainDivider:SetPoint("LEFT", panel, "LEFT")
	mainDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)

	local locked = mini:Checkbox({
		Parent = panel,
		LabelText = "Locked",
		Tooltip = "Locks the position of all bars so they can't be accidentally moved.",
		GetValue = function()
			return db.Locked
		end,
		SetValue = function(value)
			db.Locked = value
			db.Pet.Locked = value
			addon:Reload()
		end,
	})

	locked:SetPoint("TOPLEFT", mainDivider, "BOTTOMLEFT", 0, -verticalSpacing)

	local alwaysShowChk = mini:Checkbox({
		Parent = panel,
		LabelText = "Always show",
		Tooltip = "Whether to always show, or only show in combat.",
		GetValue = function()
			return db.AlwaysShow
		end,
		SetValue = function(value)
			db.AlwaysShow = value
			addon:Reload()
		end,
	})

	alwaysShowChk:SetPoint("TOP", locked, "TOP", 0, 0)
	alwaysShowChk:SetPoint("LEFT", panel, "LEFT", columnStep, 0)

	local showText = mini:Checkbox({
		Parent = panel,
		LabelText = "Show text",
		Tooltip = "Whether to show hp and power text inside the bars.",
		GetValue = function()
			return db.ShowText
		end,
		SetValue = function(value)
			db.ShowText = value
			addon:Reload()
		end,
	})

	showText:SetPoint("TOP", locked, "TOP", 0, 0)
	showText:SetPoint("LEFT", panel, "LEFT", columnStep * 2, 0)

	local usePercent = mini:Checkbox({
		Parent = panel,
		LabelText = "Percentages",
		Tooltip = "Show health and power as percentage when text is enabled.",
		GetValue = function()
			return db.UsePercent
		end,
		SetValue = function(value)
			db.UsePercent = value
			addon:Reload()
		end,
	})

	usePercent:SetPoint("TOP", locked, "TOP", 0, 0)
	usePercent:SetPoint("LEFT", panel, "LEFT", columnStep * 3, 0)

	local showPetBar = mini:Checkbox({
		Parent = panel,
		LabelText = "Show pet bar",
		Tooltip = "Show a separate health bar for your pet.",
		GetValue = function()
			return db.ShowPetBar
		end,
		SetValue = function(value)
			db.ShowPetBar = value
			addon:Reload()
		end,
	})

	showPetBar:SetPoint("TOPLEFT", locked, "BOTTOMLEFT", 0, -verticalSpacing)

	local showHealth = mini:Checkbox({
		Parent = panel,
		LabelText = "Show health bar",
		Tooltip = "Whether to show the health bar.",
		GetValue = function()
			return db.ShowHealth
		end,
		SetValue = function(value)
			db.ShowHealth = value
			addon:Reload()
		end,
	})

	showHealth:SetPoint("TOP", showPetBar, "TOP", 0, 0)
	showHealth:SetPoint("LEFT", panel, "LEFT", columnStep, 0)

	local showPower = mini:Checkbox({
		Parent = panel,
		LabelText = "Show power bar",
		Tooltip = "Whether to show the power/mana bar.",
		GetValue = function()
			return db.ShowPower
		end,
		SetValue = function(value)
			db.ShowPower = value
			addon:Reload()
		end,
	})

	showPower:SetPoint("TOP", showPetBar, "TOP", 0, 0)
	showPower:SetPoint("LEFT", panel, "LEFT", columnStep * 2, 0)

	local useClassColor = mini:Checkbox({
		Parent = panel,
		LabelText = "Class color health",
		Tooltip = "Use your class color for the health bar.",
		GetValue = function()
			return db.UseClassColorHealth
		end,
		SetValue = function(value)
			db.UseClassColorHealth = value
			addon:Reload()
		end,
	})

	useClassColor:SetPoint("TOP", showPetBar, "TOP", 0, 0)
	useClassColor:SetPoint("LEFT", panel, "LEFT", columnStep * 3, 0)

	local sizeDivider = mini:Divider({
		Parent = panel,
		Text = "Size",
	})

	sizeDivider:SetPoint("TOP", showPetBar, "BOTTOM", 0, -verticalSpacing)
	sizeDivider:SetPoint("LEFT", panel, "LEFT")
	sizeDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)

	local sliderWidth = columnStep * 2 - horizontalSpacing / 2

	local widthSlider = mini:Slider({
		Parent = panel,
		Min = 100,
		Max = 400,
		Step = 10,
		Width = sliderWidth,
		LabelText = "Width",
		GetValue = function()
			return db.Width
		end,
		SetValue = function(value)
			db.Width = mini:ClampInt(value, 100, 400, dbDefaults.Width)
			addon:Reload()
		end,
	})

	widthSlider.Slider:SetPoint("TOPLEFT", sizeDivider, "BOTTOMLEFT", 0, -verticalSpacing * 3)

	local heightSlider = mini:Slider({
		Parent = panel,
		Min = 8,
		Max = 50,
		Step = 1,
		Width = sliderWidth,
		LabelText = "Height",
		GetValue = function()
			return db.Height
		end,
		SetValue = function(value)
			db.Height = mini:ClampInt(value, 8, 50, dbDefaults.Height)
			addon:Reload()
		end,
	})

	heightSlider.Slider:SetPoint("LEFT", widthSlider.Slider, "RIGHT", horizontalSpacing, 0)

	local textSizeSlider = mini:Slider({
		Parent = panel,
		Min = 8,
		Max = 32,
		Step = 1,
		Width = sliderWidth,
		LabelText = "Text Size",
		GetValue = function()
			return db.FontSize
		end,
		SetValue = function(value)
			db.FontSize = mini:ClampInt(value, 8, 32, dbDefaults.FontSize)
			addon:Reload()
		end,
	})

	textSizeSlider.Slider:SetPoint("TOPLEFT", widthSlider.Slider, "BOTTOMLEFT", 0, -verticalSpacing * 3)

	local petDivider = mini:Divider({
		Parent = panel,
		Text = "Pet Bar",
	})

	petDivider:SetPoint("TOP", textSizeSlider.Slider, "BOTTOM", 0, -verticalSpacing)
	petDivider:SetPoint("LEFT", panel, "LEFT")
	petDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)

	local petWidthSlider = mini:Slider({
		Parent = panel,
		Min = 100,
		Max = 400,
		Step = 10,
		Width = sliderWidth,
		LabelText = "Width",
		GetValue = function()
			return db.PetWidth
		end,
		SetValue = function(value)
			db.PetWidth = mini:ClampInt(value, 100, 400, dbDefaults.PetWidth)
			addon:Reload()
		end,
	})

	petWidthSlider.Slider:SetPoint("TOPLEFT", petDivider, "BOTTOMLEFT", 0, -verticalSpacing * 3)

	local petHeightSlider = mini:Slider({
		Parent = panel,
		Min = 8,
		Max = 50,
		Step = 1,
		Width = sliderWidth,
		LabelText = "Height",
		GetValue = function()
			return db.PetHeight
		end,
		SetValue = function(value)
			db.PetHeight = mini:ClampInt(value, 8, 50, dbDefaults.PetHeight)
			addon:Reload()
		end,
	})

	petHeightSlider.Slider:SetPoint("LEFT", petWidthSlider.Slider, "RIGHT", horizontalSpacing, 0)

	local textureDdl = mini:Dropdown({
		Parent = panel,
		Width = columnStep * 2,
		LabelText = "Texture",
		Items = GetTexturesList(),
		GetValue = function()
			return db.Texture
		end,
		SetValue = function(value)
			db.Texture = value
			addon:Reload()
		end,
	})

	local textureDivider = mini:Divider({
		Parent = panel,
		Text = "Look & Feel",
	})

	textureDivider:SetPoint("TOP", petWidthSlider.Slider, "BOTTOM", 0, -verticalSpacing)
	textureDivider:SetPoint("LEFT", panel, "LEFT")
	textureDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)

	textureDdl.Label:SetPoint("TOPLEFT", textureDivider, "BOTTOMLEFT", 0, -verticalSpacing * 2)

	panel:HookScript("OnShow", function()
		-- refresh the items
		textureDdl:MiniRefresh()
	end)

	-- Shield subcategory
	local overshieldPanel = CreateFrame("Frame")
	overshieldPanel.name = "Shield"
	mini:AddSubCategory(category, overshieldPanel)
	panels[#panels + 1] = overshieldPanel

	local osHeader = mini:PanelHeader({
		Parent = overshieldPanel,
		Title = "Shield",
		Description = "Configure the colour and opacity of the shield bars.",
		Gap = 6,
		Divider = "Settings",
	})

	local osEnabledChk = mini:Checkbox({
		Parent = overshieldPanel,
		LabelText = "Show shields",
		Tooltip = "Whether to show the absorb/shield indicator on the health bar.",
		GetValue = function()
			return db.Shield.Enabled
		end,
		SetValue = function(value)
			db.Shield.Enabled = value
			addon:Reload()
		end,
	})

	osEnabledChk:SetPoint("TOPLEFT", osHeader.Anchor, "BOTTOMLEFT", 0, -verticalSpacing)

	local osSwatch = mini:ColorSwatch({
		Parent = overshieldPanel,
		LabelText = "Colour",
		Tooltip = "Click to change colour and opacity",
		Size = 24,
		GetValue = function()
			local c = db.Shield.Color
			return c[1] or 1, c[2] or 1, c[3] or 1, db.Shield.Opacity or 1
		end,
		SetValue = function(r, g, b, a)
			db.Shield.Color[1] = r
			db.Shield.Color[2] = g
			db.Shield.Color[3] = b
			db.Shield.Opacity = a
		end,
		OnChange = function()
			addon:Reload()
		end,
	})

	-- The swatch anchors its own label to its right by default; this panel wants it on
	-- the left, so drop that point before re-anchoring - leaving it would make the
	-- label and the swatch depend on each other.
	osSwatch.Label:ClearAllPoints()
	osSwatch.Label:SetPoint("TOPLEFT", osEnabledChk, "BOTTOMLEFT", 0, -verticalSpacing)
	osSwatch:SetPoint("LEFT", osSwatch.Label, "RIGHT", 8, 0)

	local osSwatchHint = overshieldPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	osSwatchHint:SetPoint("LEFT", osSwatch, "RIGHT", 8, 0)
	osSwatchHint:SetText("Click to change colour and opacity")

	overshieldPanel:HookScript("OnShow", function()
		osSwatch:MiniRefresh()
	end)

	-- Incoming Heals subcategory
	local ihPanel = CreateFrame("Frame")
	ihPanel.name = "Incoming Heals"
	mini:AddSubCategory(category, ihPanel)
	panels[#panels + 1] = ihPanel

	local ihHeader = mini:PanelHeader({
		Parent = ihPanel,
		Title = "Incoming Heals",
		Description = "Configure the colour of the incoming heal prediction bar.",
		Gap = 6,
	})

	local ihDivider = mini:Divider({
		Parent = ihPanel,
		Text = "Colour",
	})

	ihDivider:SetPoint("TOP", ihHeader.Anchor, "BOTTOM", 0, -verticalSpacing)
	ihDivider:SetPoint("LEFT", ihPanel, "LEFT")
	ihDivider:SetPoint("RIGHT", ihPanel, "RIGHT", -horizontalSpacing, 0)

	local ihSwatch = mini:ColorSwatch({
		Parent = ihPanel,
		LabelText = "Colour",
		Tooltip = "Click to change colour",
		Size = 24,
		HasOpacity = false,
		GetValue = function()
			local c = db.IncomingHealColor
			return c[1] or 0, c[2] or 1, c[3] or 0, 1
		end,
		SetValue = function(r, g, b)
			db.IncomingHealColor[1] = r
			db.IncomingHealColor[2] = g
			db.IncomingHealColor[3] = b
		end,
		OnChange = function()
			addon:Reload()
		end,
	})

	-- The swatch anchors its own label to its right by default; this panel wants it on
	-- the left, so drop that point before re-anchoring - leaving it would make the
	-- label and the swatch depend on each other.
	ihSwatch.Label:ClearAllPoints()
	ihSwatch.Label:SetPoint("TOPLEFT", ihDivider, "BOTTOMLEFT", 0, -verticalSpacing)
	ihSwatch:SetPoint("LEFT", ihSwatch.Label, "RIGHT", 8, 0)

	local ihSwatchHint = ihPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ihSwatchHint:SetPoint("LEFT", ihSwatch, "RIGHT", 8, 0)
	ihSwatchHint:SetText("Click to change colour")

	ihPanel:HookScript("OnShow", function()
		ihSwatch:MiniRefresh()
	end)

	-- Power Tick subcategory. Classic only - retail regen is continuous rather than ticked,
	-- so there is nothing to point at and the panel isn't created there at all.
	if addon.PowerTick:IsSupported() then
		local tickerPanel = CreateFrame("Frame")
		tickerPanel.name = "Power Tick"
		mini:AddSubCategory(category, tickerPanel)
		panels[#panels + 1] = tickerPanel

		local tickerHeader = mini:PanelHeader({
			Parent = tickerPanel,
			Title = "Power Tick",
			Description = "Shows when your next energy or mana regen tick will land.",
			Gap = 6,
		})

		local tickerEnabledChk = mini:Checkbox({
			Parent = tickerPanel,
			LabelText = "Show power tick",
			Tooltip = "Shows a marker sweeping across the power bar that restarts on every regen tick.",
			GetValue = function()
				return db.Ticker.Enabled
			end,
			SetValue = function(value)
				db.Ticker.Enabled = value
				addon:Reload()
			end,
		})

		tickerEnabledChk:SetPoint("TOPLEFT", tickerHeader.Anchor, "BOTTOMLEFT", 0, -verticalSpacing)

		local tickerDivider = mini:Divider({
			Parent = tickerPanel,
			Text = "Appearance",
		})

		tickerDivider:SetPoint("TOP", tickerEnabledChk, "BOTTOM", 0, -verticalSpacing)
		tickerDivider:SetPoint("LEFT", tickerPanel, "LEFT")
		tickerDivider:SetPoint("RIGHT", tickerPanel, "RIGHT", -horizontalSpacing, 0)

		local tickerThicknessSlider = mini:Slider({
			Parent = tickerPanel,
			Min = 1,
			Max = 10,
			Step = 1,
			Width = sliderWidth,
			LabelText = "Thickness",
			GetValue = function()
				return db.Ticker.Thickness
			end,
			SetValue = function(value)
				db.Ticker.Thickness = mini:ClampInt(value, 1, 10, dbDefaults.Ticker.Thickness)
				addon:Reload()
			end,
		})

		tickerThicknessSlider.Slider:SetPoint("TOPLEFT", tickerDivider, "BOTTOMLEFT", 0, -verticalSpacing * 3)

		-- Same as the shield panel: the swatch anchors its own label to its right by default,
		-- so drop that point before re-anchoring the label to the left.
		local tickerSwatch = mini:ColorSwatch({
			Parent = tickerPanel,
			LabelText = "Colour",
			Tooltip = "Click to change colour and opacity",
			Size = 24,
			GetValue = function()
				local c = db.Ticker.Color
				return c[1] or 1, c[2] or 1, c[3] or 1, db.Ticker.Opacity or 1
			end,
			SetValue = function(r, g, b, a)
				db.Ticker.Color[1] = r
				db.Ticker.Color[2] = g
				db.Ticker.Color[3] = b
				db.Ticker.Opacity = a
			end,
			OnChange = function()
				addon:Reload()
			end,
		})

		tickerSwatch.Label:ClearAllPoints()
		tickerSwatch.Label:SetPoint("TOPLEFT", tickerThicknessSlider.Slider, "BOTTOMLEFT", 0, -verticalSpacing * 2)
		tickerSwatch:SetPoint("LEFT", tickerSwatch.Label, "RIGHT", 8, 0)

		local tickerSwatchHint = tickerPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		tickerSwatchHint:SetPoint("LEFT", tickerSwatch, "RIGHT", 8, 0)
		tickerSwatchHint:SetText("Click to change colour and opacity")

		tickerPanel:HookScript("OnShow", function()
			tickerSwatch:MiniRefresh()
		end)
	end

	-- Misc subcategory
	local miscPanel = CreateFrame("Frame")
	miscPanel.name = "Misc"
	mini:AddSubCategory(category, miscPanel)
	panels[#panels + 1] = miscPanel

	local miscHeader = mini:PanelHeader({
		Parent = miscPanel,
		Title = "Misc",
		Description = "Miscellaneous settings.",
		Gap = 6,
	})

	local miscDivider = mini:Divider({
		Parent = miscPanel,
		Text = "Visibility",
	})

	miscDivider:SetPoint("TOP", miscHeader.Anchor, "BOTTOM", 0, -verticalSpacing)
	miscDivider:SetPoint("LEFT", miscPanel, "LEFT")
	miscDivider:SetPoint("RIGHT", miscPanel, "RIGHT", -horizontalSpacing, 0)

	local hideTextSuffixChk = mini:Checkbox({
		Parent = miscPanel,
		LabelText = "Hide text suffix",
		Tooltip = "Hides suffixes on bar text, such as '%' for percentages and 'K' for large numbers.",
		GetValue = function()
			return db.HideTextSuffix
		end,
		SetValue = function(value)
			db.HideTextSuffix = value
			addon:Reload()
		end,
	})

	hideTextSuffixChk:SetPoint("TOPLEFT", miscDivider, "BOTTOMLEFT", 0, -verticalSpacing)

	local outOfCombatOpacityLabel = miscPanel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	outOfCombatOpacityLabel:SetPoint("TOPLEFT", hideTextSuffixChk, "BOTTOMLEFT", 0, -verticalSpacing)
	outOfCombatOpacityLabel:SetText("Out of combat opacity")

	local outOfCombatOpacitySlider = mini:Slider({
		Parent = miscPanel,
		Min = 0,
		Max = 1,
		Step = 0.05,
		Width = sliderWidth,
		GetValue = function()
			return db.OutOfCombatOpacity or 1
		end,
		SetValue = function(value)
			db.OutOfCombatOpacity = math.max(0, math.min(1, value))
			addon:Reload()
		end,
	})

	outOfCombatOpacitySlider.Slider:SetPoint("TOPLEFT", outOfCombatOpacityLabel, "BOTTOMLEFT", 0, -verticalSpacing * 3)

	SLASH_MINIRESOURCEDISPLAY1 = "/mrd"
	SLASH_MINIRESOURCEDISPLAY2 = "/minird"
	SLASH_MINIRESOURCEDISPLAY3 = "/miniresourcedisplay"
	SlashCmdList.MINIRESOURCEDISPLAY = function(msg)
		msg = (msg or ""):lower():match("^%s*(.-)%s*$")

		if msg == "reset" then
			ResetToDefaults()
			return
		elseif msg == "tick" and addon.PowerTick:IsSupported() then
			for _, line in ipairs(addon.PowerTick:Describe()) do
				mini:NotifyWithPrefix(line)
			end
			return
		elseif msg and msg ~= "" then
			mini:NotifyWithPrefix("Commands:")
			mini:NotifyWithPrefix("/mrd reset")

			if addon.PowerTick:IsSupported() then
				mini:NotifyWithPrefix("/mrd tick")
			end

			return
		end

		mini:OpenSettings(category, panel)
	end
end

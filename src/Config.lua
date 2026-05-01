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

	Texture = "Interface\\TARGETINGFRAME\\UI-StatusBar",
	Border = true,

	HealthColor = { 0, 1, 0 },
	PowerColor = { 0.2, 0.6, 1.0 },
	PowerUseTypeColor = true,

	AlwaysShow = false,

	UsePercent = false,

	FadeInDuration = 1,
	FadeOutDuration = 1,

	HealthTextFormat = "%s/%s",
	PowerTextFormat = "%s/%s",

	ShowPetBar = false,
	PetWidth = 150,
	PetHeight = 15,

	Shield = {
		Color = { 1, 1, 1 },
		Opacity = 1,
	},

	IncomingHealColor = { 0, 1, 0 },

	Pet = {
		Point = "CENTER",
		RelativeTo = "UIParent",
		RelativePoint = "CENTER",
		X = 0,
		Y = -165,
		Locked = false,
	},
}
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
	db = mini:GetSavedVars(dbDefaults)

	-- Migrate renamed db key: Overshield -> Shield
	if db.Overshield then
		db.Shield = db.Overshield
		db.Overshield = nil
	end

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local verticalSpacing = mini.VerticalSpacing
	local horizontalSpacing = mini.HorizontalSpacing
	local columns = 4
	local columnStep = mini:ColumnWidth(columns, mini.HorizontalSpacing, 0)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -16)
	title:SetText(addonName)

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("Shows simple personal resource style health and power bars.")

	local mainDivider = mini:Divider({
		Parent = panel,
		Text = "Settings",
	})

	mainDivider:SetPoint("TOP", subtitle, "BOTTOM", 0, -verticalSpacing)
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
		Max = 20,
		Step = 1,
		Width = sliderWidth,
		LabelText = "Text Size",
		GetValue = function()
			return db.FontSize
		end,
		SetValue = function(value)
			db.FontSize = mini:ClampInt(value, 8, 20, dbDefaults.FontSize)
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
		textureDdl.Dropdown:MiniRefresh()
	end)

	-- Shield subcategory
	local overshieldPanel = CreateFrame("Frame")
	overshieldPanel.name = "Shield"
	mini:AddSubCategory(category, overshieldPanel)

	local osTitle = overshieldPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	osTitle:SetPoint("TOPLEFT", 0, -16)
	osTitle:SetText("Shield")

	local osSubtitle = overshieldPanel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	osSubtitle:SetPoint("TOPLEFT", osTitle, "BOTTOMLEFT", 0, -6)
	osSubtitle:SetText("Configure the colour and opacity of the shield bars.")

	local osDivider = mini:Divider({
		Parent = overshieldPanel,
		Text = "Colour & Opacity",
	})

	osDivider:SetPoint("TOP", osSubtitle, "BOTTOM", 0, -verticalSpacing)
	osDivider:SetPoint("LEFT", overshieldPanel, "LEFT")
	osDivider:SetPoint("RIGHT", overshieldPanel, "RIGHT", -horizontalSpacing, 0)

	local osSwatchLabel = overshieldPanel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	osSwatchLabel:SetPoint("TOPLEFT", osDivider, "BOTTOMLEFT", 0, -verticalSpacing)
	osSwatchLabel:SetText("Colour")

	local osSwatch = CreateFrame("Button", nil, overshieldPanel)
	osSwatch:SetSize(24, 24)
	osSwatch:SetPoint("LEFT", osSwatchLabel, "RIGHT", 8, 0)

	local osSwatchTex = osSwatch:CreateTexture(nil, "BACKGROUND")
	osSwatchTex:SetAllPoints(true)

	local osSwatchBorder = CreateFrame("Frame", nil, osSwatch, "BackdropTemplate")
	osSwatchBorder:SetAllPoints(true)
	osSwatchBorder:SetFrameLevel(osSwatch:GetFrameLevel() + 1)
	osSwatchBorder:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	osSwatchBorder:SetBackdropBorderColor(1, 1, 1, 1)

	local osSwatchHint = overshieldPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	osSwatchHint:SetPoint("LEFT", osSwatch, "RIGHT", 8, 0)
	osSwatchHint:SetText("Click to change colour and opacity")

	osSwatch:SetScript("OnEnter", function(self)
		osSwatchBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to change colour and opacity", 1, 1, 1)
		GameTooltip:Show()
	end)

	osSwatch:SetScript("OnLeave", function()
		osSwatchBorder:SetBackdropBorderColor(1, 1, 1, 1)
		GameTooltip:Hide()
	end)

	local function UpdateOSSwatch()
		local c = db.Shield.Color
		osSwatchTex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	end

	UpdateOSSwatch()

	osSwatch:SetScript("OnClick", function()
		local c = db.Shield.Color

		local function OnChanged()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = ColorPickerFrame:GetColorAlpha()
			db.Shield.Color[1] = r
			db.Shield.Color[2] = g
			db.Shield.Color[3] = b
			db.Shield.Opacity = a
			UpdateOSSwatch()
			addon:Reload()
		end

		local function OnCancel()
			local r, g, b, a = ColorPickerFrame:GetPreviousValues()
			db.Shield.Color[1] = r
			db.Shield.Color[2] = g
			db.Shield.Color[3] = b
			db.Shield.Opacity = a
			UpdateOSSwatch()
			addon:Reload()
		end

		ColorPickerFrame:SetupColorPickerAndShow({
			swatchFunc = OnChanged,
			opacityFunc = OnChanged,
			cancelFunc = OnCancel,
			hasOpacity = true,
			opacity = db.Shield.Opacity or 1,
			r = c[1] or 1,
			g = c[2] or 1,
			b = c[3] or 1,
		})
	end)

	overshieldPanel:HookScript("OnShow", UpdateOSSwatch)

	-- Incoming Heals subcategory
	local ihPanel = CreateFrame("Frame")
	ihPanel.name = "Incoming Heals"
	mini:AddSubCategory(category, ihPanel)

	local ihTitle = ihPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	ihTitle:SetPoint("TOPLEFT", 0, -16)
	ihTitle:SetText("Incoming Heals")

	local ihSubtitle = ihPanel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	ihSubtitle:SetPoint("TOPLEFT", ihTitle, "BOTTOMLEFT", 0, -6)
	ihSubtitle:SetText("Configure the colour of the incoming heal prediction bar.")

	local ihDivider = mini:Divider({
		Parent = ihPanel,
		Text = "Colour",
	})

	ihDivider:SetPoint("TOP", ihSubtitle, "BOTTOM", 0, -verticalSpacing)
	ihDivider:SetPoint("LEFT", ihPanel, "LEFT")
	ihDivider:SetPoint("RIGHT", ihPanel, "RIGHT", -horizontalSpacing, 0)

	local ihSwatchLabel = ihPanel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	ihSwatchLabel:SetPoint("TOPLEFT", ihDivider, "BOTTOMLEFT", 0, -verticalSpacing)
	ihSwatchLabel:SetText("Colour")

	local ihSwatch = CreateFrame("Button", nil, ihPanel)
	ihSwatch:SetSize(24, 24)
	ihSwatch:SetPoint("LEFT", ihSwatchLabel, "RIGHT", 8, 0)

	local ihSwatchTex = ihSwatch:CreateTexture(nil, "BACKGROUND")
	ihSwatchTex:SetAllPoints(true)

	local ihSwatchBorder = CreateFrame("Frame", nil, ihSwatch, "BackdropTemplate")
	ihSwatchBorder:SetAllPoints(true)
	ihSwatchBorder:SetFrameLevel(ihSwatch:GetFrameLevel() + 1)
	ihSwatchBorder:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	ihSwatchBorder:SetBackdropBorderColor(1, 1, 1, 1)

	local ihSwatchHint = ihPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ihSwatchHint:SetPoint("LEFT", ihSwatch, "RIGHT", 8, 0)
	ihSwatchHint:SetText("Click to change colour")

	ihSwatch:SetScript("OnEnter", function(self)
		ihSwatchBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to change colour", 1, 1, 1)
		GameTooltip:Show()
	end)

	ihSwatch:SetScript("OnLeave", function()
		ihSwatchBorder:SetBackdropBorderColor(1, 1, 1, 1)
		GameTooltip:Hide()
	end)

	local function UpdateIHSwatch()
		local c = db.IncomingHealColor
		ihSwatchTex:SetColorTexture(c[1] or 0, c[2] or 1, c[3] or 0, 1)
	end

	UpdateIHSwatch()

	ihSwatch:SetScript("OnClick", function()
		local c = db.IncomingHealColor

		local function OnChanged()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			db.IncomingHealColor[1] = r
			db.IncomingHealColor[2] = g
			db.IncomingHealColor[3] = b
			UpdateIHSwatch()
			addon:Reload()
		end

		local function OnCancel()
			local r, g, b = ColorPickerFrame:GetPreviousValues()
			db.IncomingHealColor[1] = r
			db.IncomingHealColor[2] = g
			db.IncomingHealColor[3] = b
			UpdateIHSwatch()
			addon:Reload()
		end

		ColorPickerFrame:SetupColorPickerAndShow({
			swatchFunc = OnChanged,
			cancelFunc = OnCancel,
			hasOpacity = false,
			r = c[1] or 0,
			g = c[2] or 1,
			b = c[3] or 0,
		})
	end)

	ihPanel:HookScript("OnShow", UpdateIHSwatch)

	SLASH_MINIRESOURCEDISPLAY1 = "/mrd"
	SLASH_MINIRESOURCEDISPLAY2 = "/minird"
	SLASH_MINIRESOURCEDISPLAY3 = "/miniresourcedisplay"
	SlashCmdList.MINIRESOURCEDISPLAY = function(msg)
		msg = (msg or ""):lower():match("^%s*(.-)%s*$")

		if msg == "reset" then
			db = mini:ResetSavedVars(dbDefaults)
			panel:MiniRefresh()
			addon:Reload()
			return
		elseif msg and msg ~= "" then
			mini:Notify("Commands:")
			mini:Notify("/mrd reset")
			return
		end

		mini:OpenSettings(category, panel)
	end
end

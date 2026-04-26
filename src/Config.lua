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

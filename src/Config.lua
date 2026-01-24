local addonName, addon = ...
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

	Scale = 1.0,
	Width = 150,
	Height = 15,

	Gap = 0,
	Padding = 2,

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

	FadeInDuration = 1,
	FadeOutDuration = 1,

	HealthTextFormat = "%s/%s",
	PowerTextFormat = "%s/%s",
}

local M = {}

addon.Config = M

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

	local locked = mini:Checkbox({
		Parent = panel,
		LabelText = "Locked",
		Tooltip = "Locks the position so it can't be accidentally moved.",
		GetValue = function()
			return db.Locked
		end,
		SetValue = function(value)
			db.Locked = value
			addon:Reload()
		end,
	})

	locked:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -verticalSpacing)

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

	alwaysShowChk:SetPoint("LEFT", locked, "RIGHT", columnStep, 0)

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

	showText:SetPoint("LEFT", alwaysShowChk, "RIGHT", columnStep, 0)

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
			db.Width = mini:ClampInt(value, 100, 400, 150)
			addon:Reload()
		end,
	})

	widthSlider.Slider:SetPoint("TOPLEFT", locked, "BOTTOMLEFT", 0, -verticalSpacing * 3)

	local heightSlider = mini:Slider({
		Parent = panel,
		Min = 10,
		Max = 50,
		Step = 1,
		Width = sliderWidth,
		LabelText = "Height",
		GetValue = function()
			return db.Height
		end,
		SetValue = function(value)
			db.Height = mini:ClampInt(value, 10, 50, 15)
			addon:Reload()
		end,
	})

	heightSlider.Slider:SetPoint("LEFT", widthSlider.Slider, "RIGHT", horizontalSpacing, 0)

	SLASH_MINIRESOURCEDISPLAY1 = "/mrd"
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

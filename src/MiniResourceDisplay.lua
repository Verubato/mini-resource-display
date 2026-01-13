local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local eventsFrame
local container
local healthBar
local powerBar
local healthText
local powerText
---@type Db
local db

local function SafeGetRelativeFrame(name)
	if type(name) ~= "string" or name == "" then
		return UIParent
	end

	return _G[name] or UIParent
end

local function ApplyPosition()
	container:ClearAllPoints()
	container:SetPoint(
		db.Point or "CENTER",
		SafeGetRelativeFrame(db.RelativeTo),
		db.RelativePoint or "CENTER",
		db.X or 0,
		db.Y or 0
	)
end

local function AddBlackOutline(frame)
	local outline = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	outline:SetPoint("TOPLEFT", frame, -1, 1)
	outline:SetPoint("BOTTOMRIGHT", frame, 1, -1)

	local lvl = frame.GetFrameLevel and frame:GetFrameLevel() or 0
	outline:SetFrameLevel(lvl + 10)

	outline:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})

	outline:SetBackdropBorderColor(0, 0, 0, 1)

	return outline
end

local function CreateStatusBar(parent)
	local tex = db.Texture or "Interface\\TARGETINGFRAME\\UI-StatusBar"
	local bar = CreateFrame("StatusBar", nil, parent)

	bar:SetStatusBarTexture(tex)

	local sbTex = bar:GetStatusBarTexture()
	if sbTex then
		sbTex:SetHorizTile(false)
		sbTex:SetVertTile(false)
	end

	bar.Background = bar:CreateTexture(nil, "BACKGROUND")
	bar.Background:SetAllPoints(true)
	bar.Background:SetTexture(tex)

	return bar
end

local function SetBarColor(bar, r, g, b)
	r = r or 1
	g = g or 1
	b = b or 1

	bar:SetStatusBarColor(r, g, b, 1)

	if bar.Background then
		bar.Background:SetVertexColor(0.1, 0.1, 0.1, 0.5)
	end
end

local function UpdateSizes()
	local pad = db.Padding or 0
	local gap = db.Gap or 0
	local w = db.Width or 150
	local h = db.Height or 15

	local totalWidth = w + pad * 2
	local totalHeight = (h * 2) + gap + pad * 2

	container:SetScale(db.Scale or 1)
	container:SetSize(totalWidth, totalHeight)

	healthBar:ClearAllPoints()
	healthBar:SetPoint("TOPLEFT", container, "TOPLEFT", pad, -pad)
	healthBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -pad, -pad)
	healthBar:SetHeight(h)

	powerBar:ClearAllPoints()
	powerBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -gap)
	powerBar:SetPoint("TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, -gap)
	powerBar:SetHeight(h)

	if db.ShowText then
		healthText:Show()
		powerText:Show()
	else
		healthText:Hide()
		powerText:Hide()
	end

	if db.FontShadow then
		healthText:SetShadowOffset(1, -1)
		healthText:SetShadowColor(0, 0, 0, 1)

		powerText:SetShadowOffset(1, -1)
		powerText:SetShadowColor(0, 0, 0, 1)
	end
end

local function UpdateHealth()
	local hp = UnitHealth("player") or 0
	local max = UnitHealthMax("player") or 1

	healthBar:SetMinMaxValues(0, max)
	healthBar:SetValue(hp)

	if db.ShowText then
		local format = db.HealthTextFormat or "%s/%s"
		local currentHpAbbreviated = AbbreviateNumbers(hp)
		local maxHpAbbreviated = AbbreviateNumbers(max)

		healthText:SetText(string.format(format, currentHpAbbreviated, maxHpAbbreviated))
	end
end

local function GetPowerColor()
	if db.PowerUseTypeColor then
		local pType = UnitPowerType("player")
		local color = PowerBarColor and PowerBarColor[pType]
		if color and color.r and color.g and color.b then
			return color.r, color.g, color.b
		end
	end

	if db.PowerColor then
		return db.PowerColor[1] or 1, db.PowerColor[2] or 1, db.PowerColor[3] or 1
	end

	return 0.2, 0.6, 1.0
end

local function UpdatePower()
	local powerType = UnitPowerType("player")
	local power = UnitPower("player", powerType) or 0
	local max = UnitPowerMax("player", powerType) or 1

	powerBar:SetMinMaxValues(0, max)
	powerBar:SetValue(power)

	local r, g, b = GetPowerColor()

	SetBarColor(powerBar, r, g, b)

	if db.ShowText then
		local format = db.PowerTextFormat or "%s/%s"
		local currentPowerAbbreviated = AbbreviateNumbers(power)
		local maxPowerAbbreviated = AbbreviateNumbers(max)

		powerText:SetText(string.format(format, currentPowerAbbreviated, maxPowerAbbreviated))
	end
end

local function UpdateColors()
	local hr = (db.HealthColor and db.HealthColor[1]) or 0
	local hg = (db.HealthColor and db.HealthColor[2]) or 1
	local hb = (db.HealthColor and db.HealthColor[3]) or 0

	SetBarColor(healthBar, hr, hg, hb)

	local r, g, b = GetPowerColor()

	SetBarColor(powerBar, r, g, b)
end

local function CreateFadeAnimations()
	container.FadeIn = container:CreateAnimationGroup()

	local fadeInAlpha = container.FadeIn:CreateAnimation("Alpha")
	fadeInAlpha:SetOrder(1)
	fadeInAlpha:SetFromAlpha(0)
	fadeInAlpha:SetToAlpha(1)
	fadeInAlpha:SetSmoothing("OUT")
	container.FadeIn.Alpha = fadeInAlpha

	container.FadeIn:SetScript("OnPlay", function()
		container:Show()
	end)

	container.FadeIn:SetScript("OnFinished", function()
		if container.IsShowing then
			container:SetAlpha(1)
		end
	end)

	container.FadeOut = container:CreateAnimationGroup()

	local fadeOutAlpha = container.FadeOut:CreateAnimation("Alpha")
	fadeOutAlpha:SetOrder(1)
	fadeOutAlpha:SetFromAlpha(1)
	fadeOutAlpha:SetToAlpha(0)
	fadeOutAlpha:SetSmoothing("OUT")
	container.FadeOut.Alpha = fadeOutAlpha

	container.FadeOut:SetScript("OnFinished", function()
		if not container.IsShowing then
			container:Hide()
		end
	end)
end

local function FadeTo(show)
	CreateFadeAnimations()

	if container.IsShowing == show then
		return
	end

	container.IsShowing = show and true or false

	if show then
		if container.FadeOut and container.FadeOut:IsPlaying() then
			container.FadeOut:Stop()
		end

		if container.FadeIn and container.FadeIn.Alpha then
			container.FadeIn.Alpha:SetDuration(db.FadeInDuration or 1)
			container.FadeIn.Alpha:SetFromAlpha(0)
			container.FadeIn.Alpha:SetToAlpha(1)

			container.FadeIn:Stop()
			container.FadeIn:Play()
		else
			container:SetAlpha(1)
			container:Show()
		end
	else
		if container.FadeIn and container.FadeIn:IsPlaying() then
			container.FadeIn:Stop()
		end

		if container.FadeOut and container.FadeOut.Alpha then
			container.FadeOut.Alpha:SetDuration(db.FadeOutDuration or 1)
			container.FadeOut.Alpha:SetFromAlpha(1)
			container.FadeOut.Alpha:SetToAlpha(0)

			container.FadeOut:Stop()
			container.FadeOut:Play()
		else
			container:SetAlpha(0)
			container:Hide()
		end
	end
end

local function UpdateVisibility()
	if db.AlwaysShow then
		FadeTo(true)
		return
	end

	FadeTo(UnitAffectingCombat("player"))
end

local function Load()
	container = CreateFrame("Frame", addonName .. "Frame", UIParent, "BackdropTemplate")
	container:SetClampedToScreen(true)
	container:EnableMouse(true)
	container:SetMovable(true)
	container:RegisterForDrag("LeftButton")
	container:SetScript("OnDragStart", container.StartMoving)
	container:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint(1)
		db.Point = point
		db.RelativePoint = relativePoint
		db.X = math.floor((x or 0) + 0.5)
		db.Y = math.floor((y or 0) + 0.5)
	end)

	container:SetAlpha(0)
	container:Hide()

	CreateFadeAnimations()

	healthBar = CreateStatusBar(container)
	powerBar = CreateStatusBar(container)

	local baseLevel = container:GetFrameLevel() or 0
	healthBar:SetFrameLevel(baseLevel + 1)
	powerBar:SetFrameLevel(baseLevel + 1)

	if db.Border then
		healthBar.Outline = AddBlackOutline(healthBar)
		powerBar.Outline = AddBlackOutline(powerBar)
	end

	healthText = healthBar:CreateFontString(nil, "OVERLAY")
	healthText:SetFont(db.Font or "Fonts\\FRIZQT__.TTF", db.FontSize or 11, db.FontFlags or "OUTLINE")
	healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)

	powerText = powerBar:CreateFontString(nil, "OVERLAY")
	powerText:SetFont(db.Font or "Fonts\\FRIZQT__.TTF", db.FontSize or 11, db.FontFlags or "OUTLINE")
	powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)

	addon:Reload()
end

local function OnEvent(_, event, arg1)
	if event == "PLAYER_ENTERING_WORLD" then
		UpdateVisibility()
		UpdateHealth()
		UpdatePower()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		UpdateVisibility()
		return
	end

	if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" then
		if arg1 == "player" then
			UpdateHealth()
		end
		return
	end

	if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_DISPLAYPOWER" then
		if arg1 == "player" then
			UpdatePower()
		end
		return
	end
end

local function OnAddonLoaded()
	addon.Config:Init()

	db = mini:GetSavedVars()

	Load()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	eventsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

	if eventsFrame.RegisterUnitEvent then
		eventsFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
		eventsFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		eventsFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		eventsFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	else
		eventsFrame:RegisterEvent("UNIT_HEALTH")
		eventsFrame:RegisterEvent("UNIT_POWER_UPDATE")
		eventsFrame:RegisterEvent("UNIT_POWER_FREQUENT")
		eventsFrame:RegisterEvent("UNIT_DISPLAYPOWER")
	end

	eventsFrame:SetScript("OnEvent", OnEvent)
end

function addon:Reload()
	ApplyPosition()
	UpdateSizes()
	UpdateColors()
	UpdateVisibility()
	UpdateHealth()
	UpdatePower()
end

mini:WaitForAddonLoad(OnAddonLoaded)

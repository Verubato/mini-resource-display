local addonName = ...
local db
local loader
local container
local healthBar
local powerBar
local healthText
local powerText
local dbDefaults = {
	Point = "CENTER",
	RelativeTo = "UIParent",
	RelativePoint = "CENTER",
	X = 0,
	Y = -140,

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

local function Notify(msg)
	local formatted = string.format("Mini Resource Display - %s.", msg)
	print(formatted)
end

local function CopyTable(src, dst)
	if type(dst) ~= "table" then
		dst = {}
	end

	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyTable(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end

	return dst
end

local function SafeGetRelativeFrame(name)
	if type(name) ~= "string" or name == "" then
		return UIParent
	end
	return _G[name] or UIParent
end

local function ApplyPosition()
	if not container or not db then
		return
	end

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
	if not frame then
		return nil
	end

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
	if not parent then
		return nil
	end

	local tex = (db and db.Texture) or "Interface\\TARGETINGFRAME\\UI-StatusBar"

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

	if healthText and powerText then
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
end

local function FormatWithCommas(value)
	if not value then
		return "0"
	end

	value = math.floor(tonumber(value) or 0)
	local numString = tostring(value)
	local result = numString:reverse():gsub("(%d%d%d)", "%1,"):reverse()

	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end

	return result
end

local function FormatValue(value)
	if not value then
		return "0"
	end

	value = tonumber(value) or 0

	if value > 1000 then
		local thousands = math.floor(value / 1000)
		return FormatWithCommas(thousands) .. "K"
	end

	return tostring(math.floor(value))
end

local function UpdateHealth()
	local cur = UnitHealth("player") or 0
	local max = UnitHealthMax("player") or 1

	if max <= 0 then
		max = 1
	end

	local pct = (cur / max) * 100

	if pct < 0 then
		pct = 0
	end

	if pct > 100 then
		pct = 100
	end

	healthBar:SetMinMaxValues(0, 100)
	healthBar:SetValue(pct)

	if db.ShowText and healthText then
		local format = db.HealthTextFormat or "%s/%s"
		healthText:SetText(format:format(FormatValue(cur), FormatValue(max)))
	end
end

local function GetPowerColor()
	if db and db.PowerUseTypeColor then
		local pType = UnitPowerType("player")
		local color = PowerBarColor and PowerBarColor[pType]
		if color and color.r and color.g and color.b then
			return color.r, color.g, color.b
		end
	end

	if db and db.PowerColor then
		return db.PowerColor[1] or 1, db.PowerColor[2] or 1, db.PowerColor[3] or 1
	end

	return 0.2, 0.6, 1.0
end

local function UpdatePower()
	local powerType = UnitPowerType("player")
	local cur = UnitPower("player", powerType) or 0
	local max = UnitPowerMax("player", powerType) or 1

	if max <= 0 then
		max = 1
	end

	local pct = (cur / max) * 100

	if pct < 0 then
		pct = 0
	end

	if pct > 100 then
		pct = 100
	end

	powerBar:SetMinMaxValues(0, 100)
	powerBar:SetValue(pct)

	local r, g, b = GetPowerColor()

	SetBarColor(powerBar, r, g, b)

	if db.ShowText and powerText then
		local format = db.PowerTextFormat or "%s/%s"
		powerText:SetText(format:format(FormatValue(cur), FormatValue(max)))
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

local function Reset()
	PersonalResourceLiteDB = {}
	db = CopyTable(dbDefaults, PersonalResourceLiteDB)

	ApplyPosition()
	UpdateSizes()
	UpdateColors()
	UpdateVisibility()
	UpdateHealth()
	UpdatePower()

	Notify("Reset to defaults.")
end

local function Load()
	container = CreateFrame("Frame", "PersonalResourceLiteFrame", UIParent, "BackdropTemplate")
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
	if healthBar then
		healthBar:SetFrameLevel(baseLevel + 1)
	end
	if powerBar then
		powerBar:SetFrameLevel(baseLevel + 1)
	end

	if db.Border then
		if healthBar then
			healthBar.Outline = AddBlackOutline(healthBar)
		end
		if powerBar then
			powerBar.Outline = AddBlackOutline(powerBar)
		end
	end

	if healthBar then
		healthText = healthBar:CreateFontString(nil, "OVERLAY")
		healthText:SetFont(db.Font or "Fonts\\FRIZQT__.TTF", db.FontSize or 11, db.FontFlags or "OUTLINE")
		healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
	end

	if powerBar then
		powerText = powerBar:CreateFontString(nil, "OVERLAY")
		powerText:SetFont(db.Font or "Fonts\\FRIZQT__.TTF", db.FontSize or 11, db.FontFlags or "OUTLINE")
		powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
	end

	ApplyPosition()
	UpdateSizes()
	UpdateColors()
	UpdateVisibility()
	UpdateHealth()
	UpdatePower()

	SLASH_MINIRESOURCEDISPLAY1 = "/prl"
	SlashCmdList.MINIRESOURCEDISPLAY = function(msg)
		msg = (msg or ""):lower():match("^%s*(.-)%s*$")

		if msg == "reset" then
			Reset()
			return
		end

		Notify("Commands:")
		Notify("/mrd reset")
	end
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

	if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
		if arg1 == "player" then
			UpdatePower()
		end
		return
	end
end

loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		MiniResourceDisplayDB = MiniResourceDisplayDB or {}
		db = CopyTable(dbDefaults, MiniResourceDisplayDB)

		Load()

		loader:RegisterEvent("PLAYER_ENTERING_WORLD")
		loader:RegisterEvent("PLAYER_REGEN_DISABLED")
		loader:RegisterEvent("PLAYER_REGEN_ENABLED")

		if loader.RegisterUnitEvent then
			loader:RegisterUnitEvent("UNIT_HEALTH", "player")
			loader:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
			loader:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		else
			loader:RegisterEvent("UNIT_HEALTH")
			loader:RegisterEvent("UNIT_POWER_UPDATE")
			loader:RegisterEvent("UNIT_POWER_FREQUENT")
		end

		loader:SetScript("OnEvent", OnEvent)
	end
end)

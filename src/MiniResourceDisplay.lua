local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local LSM = LibStub and LibStub("LibSharedMedia-3.0", false)
local eventsFrame
local fallbackTexture = "Interface\\TARGETINGFRAME\\UI-StatusBar"
local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
---@type Db
local db

local playerGroup
local petGroup

local function SafeGetRelativeFrame(name)
	if type(name) ~= "string" or name == "" then
		return UIParent
	end

	return _G[name] or UIParent
end

local function GetConfiguredTexture()
	if db.Texture == "Blizzard" then
		return fallbackTexture
	end

	local texture

	if LSM then
		texture = LSM:Fetch("statusbar", db.Texture)
	end

	return texture or fallbackTexture
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

local function CreateBackground(statusBar)
	local background = statusBar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints(true)

	return background
end

local function SetBarColor(bar, r, g, b)
	r = r or 1
	g = g or 1
	b = b or 1

	bar:SetStatusBarColor(r, g, b, 1)

	if bar.Background then
		bar.Background:SetVertexColor(0.1, 0.1, 0.1, 1.0)
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

-- Creates a self-contained bar group for a WoW unit.
-- hasPower: whether this group includes a power bar (player=true, pet=false)
-- getPositionDb: function() → table with Point/RelativeTo/RelativePoint/X/Y/Locked
-- savePosition: function(point, relativePoint, x, y)
local function CreateBarGroup(unit, containerName, hasPower, getPositionDb, savePosition)
	local group = {
		unit = unit,
		hasPower = hasPower,
	}

	function group:SetupFadeAnimations()
		local c = self.container
		if c.FadeIn then return end

		c.FadeIn = c:CreateAnimationGroup()

		local fadeInAlpha = c.FadeIn:CreateAnimation("Alpha")
		fadeInAlpha:SetOrder(1)
		fadeInAlpha:SetFromAlpha(0)
		fadeInAlpha:SetToAlpha(1)
		fadeInAlpha:SetSmoothing("OUT")
		c.FadeIn.Alpha = fadeInAlpha

		c.FadeIn:SetScript("OnPlay", function()
			c:Show()
		end)

		c.FadeIn:SetScript("OnFinished", function()
			if c.IsShowing then
				c:SetAlpha(1)
			end
		end)

		c.FadeOut = c:CreateAnimationGroup()

		local fadeOutAlpha = c.FadeOut:CreateAnimation("Alpha")
		fadeOutAlpha:SetOrder(1)
		fadeOutAlpha:SetFromAlpha(1)
		fadeOutAlpha:SetToAlpha(0)
		fadeOutAlpha:SetSmoothing("OUT")
		c.FadeOut.Alpha = fadeOutAlpha

		c.FadeOut:SetScript("OnFinished", function()
			if not c.IsShowing then
				c:Hide()
			end
		end)
	end

	function group:FadeTo(show)
		self:SetupFadeAnimations()

		local c = self.container

		if c.IsShowing == show then
			return
		end

		c.IsShowing = show and true or false

		if show then
			if c.FadeOut and c.FadeOut:IsPlaying() then
				c.FadeOut:Stop()
			end

			if c.FadeIn and c.FadeIn.Alpha then
				c.FadeIn.Alpha:SetDuration(db.FadeInDuration or 1)
				c.FadeIn.Alpha:SetFromAlpha(0)
				c.FadeIn.Alpha:SetToAlpha(1)

				c.FadeIn:Stop()
				c.FadeIn:Play()
			else
				c:SetAlpha(1)
				c:Show()
			end
		else
			if c.FadeIn and c.FadeIn:IsPlaying() then
				c.FadeIn:Stop()
			end

			if c.FadeOut and c.FadeOut.Alpha then
				c.FadeOut.Alpha:SetDuration(db.FadeOutDuration or 1)
				c.FadeOut.Alpha:SetFromAlpha(1)
				c.FadeOut.Alpha:SetToAlpha(0)

				c.FadeOut:Stop()
				c.FadeOut:Play()
			else
				c:SetAlpha(0)
				c:Hide()
			end
		end
	end

	function group:ApplyPosition()
		local pos = getPositionDb()
		self.container:ClearAllPoints()
		self.container:SetPoint(
			pos.Point or "CENTER",
			SafeGetRelativeFrame(pos.RelativeTo),
			pos.RelativePoint or "CENTER",
			pos.X or 0,
			pos.Y or 0
		)
		self.container:EnableMouse(not pos.Locked)
		self.container:SetMovable(not pos.Locked)
	end

	function group:UpdateSizes()
		if not self.hasPower and not db.ShowPetBar then
			return
		end

		local pad = db.Padding or 0
		local gap = db.Gap or 0
		local w = (not self.hasPower and db.PetWidth) or db.Width or 150
		local h = (not self.hasPower and db.PetHeight) or db.Height or 15

		local showHealth = not self.hasPower or (db.ShowHealth ~= false)
		local showPower = self.hasPower and (db.ShowPower ~= false)

		local bars = 0
		if showHealth then bars = bars + 1 end
		if showPower then bars = bars + 1 end

		if bars > 0 then
			local totalHeight = (h * bars) + ((bars == 2) and gap or 0) + pad * 2
			self.container:SetSize(w + pad * 2, totalHeight)
			self.container:Show()
		else
			self.container:Hide()
		end

		self.healthBar:ClearAllPoints()
		self.healthBar:SetHeight(h)
		self.healthBar:SetShown(showHealth)

		if self.powerBar then
			self.powerBar:ClearAllPoints()
			self.powerBar:SetHeight(h)
			self.powerBar:SetShown(showPower)
		end

		if showHealth then
			self.healthBar:SetPoint("TOPLEFT", self.container, "TOPLEFT", pad, -pad)
			self.healthBar:SetPoint("TOPRIGHT", self.container, "TOPRIGHT", -pad, -pad)
		end

		if self.powerBar then
			if showHealth and showPower then
				self.powerBar:SetPoint("TOPLEFT", self.healthBar, "BOTTOMLEFT", 0, -gap)
				self.powerBar:SetPoint("TOPRIGHT", self.healthBar, "BOTTOMRIGHT", 0, -gap)
			elseif showPower then
				self.powerBar:SetPoint("TOPLEFT", self.container, "TOPLEFT", pad, -pad)
				self.powerBar:SetPoint("TOPRIGHT", self.container, "TOPRIGHT", -pad, -pad)
			end
		end

		if db.ShowText then
			self.healthText:SetShown(showHealth)
			if self.powerText then self.powerText:SetShown(showPower) end
		else
			self.healthText:Hide()
			if self.powerText then self.powerText:Hide() end
		end

		if db.FontShadow then
			self.healthText:SetShadowOffset(1, -1)
			self.healthText:SetShadowColor(0, 0, 0, 1)

			if self.powerText then
				self.powerText:SetShadowOffset(1, -1)
				self.powerText:SetShadowColor(0, 0, 0, 1)
			end
		else
			self.healthText:SetShadowOffset(0, 0)
			if self.powerText then self.powerText:SetShadowOffset(0, 0) end
		end
	end

	function group:UpdateHealth()
		local hp = UnitHealth(self.unit) or 0
		local max = UnitHealthMax(self.unit) or 1

		self.healthBar:SetMinMaxValues(0, max)
		self.healthBar:SetValue(hp, smoothing)

		if db.ShowText then
			if db.UsePercent then
				local pct = 0
				if type(UnitHealthPercent) == "function" then
					pct = UnitHealthPercent(self.unit, true, (CurveConstants and CurveConstants.ScaleTo100))
				else
					if max > 0 then
						pct = math.floor((hp / max) * 100 + 0.5)
					end
				end
				self.healthText:SetText(string.format("%d%%", pct))
			else
				local format = db.HealthTextFormat or "%s/%s"
				local currentHpAbbreviated = AbbreviateNumbers(hp)
				local maxHpAbbreviated = AbbreviateNumbers(max)

				self.healthText:SetText(string.format(format, currentHpAbbreviated, maxHpAbbreviated))
			end
		end

		self:UpdateAbsorb()
	end

	function group:UpdateAbsorb()
		if not self.overshieldBar then
			return
		end

		local maxHealth = UnitHealthMax(self.unit) or 0
		local totalAbsorbs = UnitGetTotalAbsorbs(self.unit) or 0

		self.overshieldBar:SetMinMaxValues(0, maxHealth)
		self.overshieldBar:SetValue(totalAbsorbs)

		if self.regularAbsorbBar then
			if self.healPredictionCalc and UnitGetDetailedHealPrediction then
				-- Midnight+: use calculator to avoid secret value arithmetic
				UnitGetDetailedHealPrediction(self.unit, nil, self.healPredictionCalc)
				local absorbAmount, clamped = self.healPredictionCalc:GetDamageAbsorbs()
				local missingHealth = self.healPredictionCalc:GetMissingHealth()
				self.regularAbsorbBar:SetMinMaxValues(0, missingHealth)
				self.regularAbsorbBar:SetValue(absorbAmount or 0)
				self.regularAbsorbBar:SetAlphaFromBoolean(clamped, 0, 1)
				self.overshieldBar:SetAlphaFromBoolean(clamped, 1, 0)
			else
				-- Legacy: values are non-secret numbers, direct math is safe
				local hp = UnitHealth(self.unit) or 0
				local remaining = math.max(0, maxHealth - hp)
				local cappedAbsorb = math.min(totalAbsorbs, remaining)
				local hasOvershield = totalAbsorbs > remaining
				self.regularAbsorbBar:SetMinMaxValues(0, remaining)
				self.regularAbsorbBar:SetValue(cappedAbsorb)
				self.regularAbsorbBar:SetAlpha(hasOvershield and 0 or 1)
				self.overshieldBar:SetAlpha(hasOvershield and 1 or 0)
			end
		end
	end

	function group:UpdatePower()
		if not self.powerBar then return end

		local powerType = UnitPowerType(self.unit)
		local power = UnitPower(self.unit, powerType) or 0
		local max = UnitPowerMax(self.unit, powerType) or 1

		self.powerBar:SetMinMaxValues(0, max)
		self.powerBar:SetValue(power, smoothing)

		local r, g, b = GetPowerColor()
		SetBarColor(self.powerBar, r, g, b)

		if db.ShowText and self.powerText then
			if db.UsePercent then
				local pct = 0
				if type(UnitPowerPercent) == "function" then
					pct = UnitPowerPercent(self.unit, powerType, true, (CurveConstants and CurveConstants.ScaleTo100))
				else
					if max > 0 then
						pct = math.floor((power / max) * 100 + 0.5)
					end
				end
				self.powerText:SetText(string.format("%d%%", pct))
			else
				local format = db.PowerTextFormat or "%s/%s"
				local currentPowerAbbreviated = AbbreviateNumbers(power)
				local maxPowerAbbreviated = AbbreviateNumbers(max)

				self.powerText:SetText(string.format(format, currentPowerAbbreviated, maxPowerAbbreviated))
			end
		end
	end

	function group:UpdateColors()
		local hr, hg, hb

		if db.UseClassColorHealth then
			local _, class = UnitClass(self.unit)
			local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			if c then
				hr, hg, hb = c.r, c.g, c.b
			end
		end

		if not hr then
			hr = (db.HealthColor and db.HealthColor[1]) or 0
			hg = (db.HealthColor and db.HealthColor[2]) or 1
			hb = (db.HealthColor and db.HealthColor[3]) or 0
		end

		SetBarColor(self.healthBar, hr, hg, hb)

		if self.regularAbsorbBar and self.regularAbsorbBar.Background then
			self.regularAbsorbBar.Background:SetVertexColor(hr, hg, hb, 1)
		end

		if self.overshieldBar and self.overshieldBar.Background then
			self.overshieldBar.Background:SetVertexColor(hr, hg, hb, 1)
		end

		if self.powerBar then
			local r, g, b = GetPowerColor()
			SetBarColor(self.powerBar, r, g, b)
		end
	end

	function group:UpdateTextures()
		local texture = GetConfiguredTexture()

		self.healthBar:SetStatusBarTexture(texture)

		local hpTexture = self.healthBar:GetStatusBarTexture()

		if hpTexture == nil then
			self.healthBar:SetStatusBarTexture(fallbackTexture)
			hpTexture = self.healthBar:GetStatusBarTexture()
		end

		if hpTexture then
			hpTexture:SetHorizTile(false)
			hpTexture:SetVertTile(false)
		end

		if texture and self.healthBar.Background then
			self.healthBar.Background:SetTexture(texture)
		end

		if self.powerBar then
			self.powerBar:SetStatusBarTexture(texture)
			local powerTexture = self.powerBar:GetStatusBarTexture()

			if powerTexture == nil then
				self.powerBar:SetStatusBarTexture(fallbackTexture)
				powerTexture = self.powerBar:GetStatusBarTexture()
			end

			if powerTexture then
				powerTexture:SetHorizTile(false)
				powerTexture:SetVertTile(false)
			end

			if texture and self.powerBar.Background then
				self.powerBar.Background:SetTexture(texture)
			end
		end

		if texture and self.regularAbsorbBar and self.regularAbsorbBar.Background then
			self.regularAbsorbBar.Background:SetTexture(texture)
		end

		if texture and self.overshieldBar and self.overshieldBar.Background then
			self.overshieldBar.Background:SetTexture(texture)
		end
	end

	function group:UpdateFonts()
		self.healthText:SetFont(db.Font or "Fonts\\FRIZQT__.TTF", db.FontSize or 11, db.FontFlags or "OUTLINE")

		if self.powerText then
			self.powerText:SetFont(db.Font or "Fonts\\FRIZQT__.TTF", db.FontSize or 11, db.FontFlags or "OUTLINE")
		end
	end

	function group:UpdateVisibility()
		if not self.hasPower then
			if not db.ShowPetBar or not UnitExists("pet") then
				self.container:SetAlpha(0)
				self.container:Hide()
				self.container.IsShowing = false
				return
			end
		end

		if db.AlwaysShow then
			self:FadeTo(true)
			return
		end

		self:FadeTo(UnitAffectingCombat("player"))
	end

	function group:Load()
		self.container = CreateFrame("Frame", containerName, UIParent, "BackdropTemplate")
		self.container:SetClampedToScreen(true)
		self.container:EnableMouse(true)
		self.container:SetMovable(true)
		self.container:RegisterForDrag("LeftButton")
		self.container:SetScript("OnDragStart", self.container.StartMoving)
		self.container:SetScript("OnDragStop", function(c)
			c:StopMovingOrSizing()
			local point, _, relativePoint, x, y = c:GetPoint(1)
			savePosition(point, relativePoint, x, y)
		end)

		self.container:SetAlpha(0)
		self.container:Hide()

		self:SetupFadeAnimations()

		self.healthBar = CreateFrame("StatusBar", nil, self.container)
		self.healthBar.Background = CreateBackground(self.healthBar)

		self.regularAbsorbBar = CreateFrame("StatusBar", nil, self.container)
		self.regularAbsorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Overlay")

		local regAbsTex = self.regularAbsorbBar:GetStatusBarTexture()
		if regAbsTex then
			regAbsTex:SetTexture("Interface\\RaidFrame\\Shield-Overlay", "REPEAT", "REPEAT")
			regAbsTex:SetHorizTile(true)
			regAbsTex:SetVertTile(true)
			regAbsTex:SetDrawLayer("ARTWORK", 1)
			regAbsTex:SetDesaturated(true)

			-- Background anchored to the fill texture's right so it only covers the absorb region
			self.regularAbsorbBar.Background = self.regularAbsorbBar:CreateTexture(nil, "BACKGROUND")
			self.regularAbsorbBar.Background:SetPoint("TOPLEFT", self.regularAbsorbBar, "TOPLEFT", 0, 0)
			self.regularAbsorbBar.Background:SetPoint("BOTTOMRIGHT", regAbsTex, "BOTTOMRIGHT", 0, 0)
		end

		self.regularAbsorbBar:SetStatusBarColor(1, 1, 1, 1)

		self.overshieldBar = CreateFrame("StatusBar", nil, self.container)
		self.overshieldBar:SetAllPoints(self.healthBar)
		self.overshieldBar:SetReverseFill(true)
		self.overshieldBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Overlay")

		local absTex = self.overshieldBar:GetStatusBarTexture()
		if absTex then
			absTex:SetTexture("Interface\\RaidFrame\\Shield-Overlay", "REPEAT", "REPEAT")
			absTex:SetHorizTile(true)
			absTex:SetVertTile(true)
			absTex:SetDrawLayer("ARTWORK", 1)
			absTex:SetDesaturated(true)

			-- Background anchored to the fill texture's left so it only covers the overshield region
			self.overshieldBar.Background = self.overshieldBar:CreateTexture(nil, "BACKGROUND")
			self.overshieldBar.Background:SetPoint("TOPRIGHT", self.overshieldBar, "TOPRIGHT", 0, 0)
			self.overshieldBar.Background:SetPoint("BOTTOMLEFT", absTex, "BOTTOMLEFT", 0, 0)
		end

		self.overshieldBar:SetStatusBarColor(1, 1, 1, 1)

		if self.hasPower then
			self.powerBar = CreateFrame("StatusBar", nil, self.container)
			self.powerBar.Background = CreateBackground(self.powerBar)
		end

		self:UpdateTextures()

		-- Anchor the regular absorb bar to the right edge of the health bar fill texture.
		-- As health changes the fill texture resizes, so this automatically tracks health end.
		self.regularAbsorbBar:SetPoint("TOPLEFT", self.healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
		self.regularAbsorbBar:SetPoint("BOTTOMRIGHT", self.healthBar, "BOTTOMRIGHT", 0, 0)

		if CreateUnitHealPredictionCalculator then
			self.healPredictionCalc = CreateUnitHealPredictionCalculator()
			self.healPredictionCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
		end

		local baseLevel = self.container:GetFrameLevel() or 0
		self.healthBar:SetFrameLevel(baseLevel + 1)
		if self.powerBar then self.powerBar:SetFrameLevel(baseLevel + 1) end
		-- Must be above healthBar so its background isn't covered by healthBar's dark background
		self.overshieldBar:SetFrameLevel(baseLevel + 2)
		self.regularAbsorbBar:SetFrameLevel(baseLevel + 2)

		if db.Border then
			self.healthBar.Outline = AddBlackOutline(self.healthBar)
			if self.powerBar then
				self.powerBar.Outline = AddBlackOutline(self.powerBar)
			end
		end

		-- Text frame above all bars so font strings aren't covered by regularAbsorbBar
		local textFrame = CreateFrame("Frame", nil, self.container)
		textFrame:SetFrameLevel(baseLevel + 3)

		self.healthText = textFrame:CreateFontString(nil, "OVERLAY")
		self.healthText:SetPoint("CENTER", self.healthBar, "CENTER", 0, 0)

		if self.powerBar then
			self.powerText = textFrame:CreateFontString(nil, "OVERLAY")
			self.powerText:SetPoint("CENTER", self.powerBar, "CENTER", 0, 0)
		end

		self:UpdateFonts()
	end

	function group:Reload()
		self:ApplyPosition()
		self:UpdateSizes()
		self:UpdateColors()
		self:UpdateVisibility()
		self:UpdateHealth()
		self:UpdateAbsorb()
		self:UpdatePower()
		self:UpdateTextures()
		self:UpdateFonts()
	end

	return group
end

local function Load()
	playerGroup = CreateBarGroup(
		"player",
		addonName .. "Frame",
		true,
		function() return db end,
		function(point, relativePoint, x, y)
			db.Point = point
			db.RelativePoint = relativePoint
			db.X = math.floor((x or 0) + 0.5)
			db.Y = math.floor((y or 0) + 0.5)
		end
	)
	playerGroup:Load()

	petGroup = CreateBarGroup(
		"pet",
		addonName .. "PetFrame",
		false,
		function() return db.Pet end,
		function(point, relativePoint, x, y)
			db.Pet.Point = point
			db.Pet.RelativePoint = relativePoint
			db.Pet.X = math.floor((x or 0) + 0.5)
			db.Pet.Y = math.floor((y or 0) + 0.5)
		end
	)
	petGroup:Load()

	addon:Reload()
end

local function OnEvent(_, event, arg1)
	if event == "PLAYER_ENTERING_WORLD" then
		playerGroup:UpdateVisibility()
		playerGroup:UpdateHealth()
		playerGroup:UpdateAbsorb()
		playerGroup:UpdatePower()
		petGroup:UpdateVisibility()
		petGroup:UpdateHealth()
		petGroup:UpdateAbsorb()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		playerGroup:UpdateVisibility()
		petGroup:UpdateVisibility()
		return
	end

	if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" then
		if arg1 == "player" then
			playerGroup:UpdateHealth()
		elseif arg1 == "pet" then
			petGroup:UpdateHealth()
		end
		return
	end

	if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_DISPLAYPOWER" then
		if arg1 == "player" then
			playerGroup:UpdatePower()
		end
		return
	end

	if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
		if arg1 == "player" then
			playerGroup:UpdateAbsorb()
		elseif arg1 == "pet" then
			petGroup:UpdateAbsorb()
		end
		return
	end

	if event == "UNIT_PET" then
		if arg1 == "player" then
			petGroup:UpdateVisibility()
			petGroup:UpdateHealth()
			petGroup:UpdateAbsorb()
		end
		return
	end
end

local function OnAddonLoaded()
	addon.Config:Init()

	db = mini:GetSavedVars()

	-- Wait for PLAYER_ENTERING_WORLD so other addons have had time to register
	-- their textures with LSM, then defer one frame tick to catch any that
	-- register during the same event cycle.
	local initFrame = CreateFrame("Frame")
	initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	initFrame:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		self:SetScript("OnEvent", nil)

		C_Timer.After(0, function()
			Load()

			eventsFrame = CreateFrame("Frame")
			eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
			eventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
			eventsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			eventsFrame:RegisterEvent("UNIT_PET")

			if eventsFrame.RegisterUnitEvent then
				eventsFrame:RegisterUnitEvent("UNIT_HEALTH", "player", "pet")
				eventsFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
				eventsFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
				eventsFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
				eventsFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player", "pet")
				eventsFrame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player", "pet")
			else
				eventsFrame:RegisterEvent("UNIT_HEALTH")
				eventsFrame:RegisterEvent("UNIT_POWER_UPDATE")
				eventsFrame:RegisterEvent("UNIT_POWER_FREQUENT")
				eventsFrame:RegisterEvent("UNIT_DISPLAYPOWER")
				eventsFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
				eventsFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
			end

			eventsFrame:SetScript("OnEvent", OnEvent)
		end)
	end)
end

function addon:Reload()
	playerGroup:Reload()
	petGroup:Reload()
end

mini:WaitForAddonLoad(OnAddonLoaded)

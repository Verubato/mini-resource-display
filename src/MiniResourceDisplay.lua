local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local eventsFrame
-- The "Blizzard" entry is a sentinel name rather than a file LSM can resolve.
local fallbackTexture = "Interface\\TARGETINGFRAME\\UI-StatusBar"
addon.BlizzardStatusBarTexture = fallbackTexture
local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
---@type Db
local db

local playerGroup
local petGroup
local mediaSubscribed = false
local textureRefreshQueued = false

-- Blood, unholy, frost, death, in GetRuneType's own order.
local RUNE_TYPE_COLORS = {
	{ 0.77, 0.12, 0.23 },
	{ 0.20, 0.80, 0.20 },
	{ 0.10, 0.70, 0.90 },
	{ 0.55, 0.55, 0.55 },
}

-- Retail spec id to its tree's RUNE_TYPE_COLORS entry.
local SPEC_RUNE_COLOR_INDEX = {
	[250] = 1, -- Blood
	[252] = 2, -- Unholy
	[251] = 3, -- Frost
}

local RUNE_UPDATE_INTERVAL = 0.1

-- Enum.PowerType field names, as UNIT_POWER_UPDATE/FREQUENT's own powerToken argument spells them.
local POWER_TOKEN_BY_FIELD = {
	ComboPoints = "COMBO_POINTS",
	HolyPower = "HOLY_POWER",
	Chi = "CHI",
	SoulShards = "SOUL_SHARDS",
	ArcaneCharges = "ARCANE_CHARGES",
	Essence = "ESSENCE",
	BurningEmbers = "BURNING_EMBERS",
	ShadowOrbs = "SHADOW_ORBS",
}

---Hoisted because an inline comparator is a fresh closure per sort, and this one can sort ten
---times a second.
local function CompareRuneReadiness(a, b)
	if a.Ready ~= b.Ready then
		return a.Ready
	end

	return a.Remaining < b.Remaining
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

---Re-applies the configured texture to whichever bar groups have loaded, so a texture pack
---that registers after login corrects the bars.
local function RefreshTextures()
	if playerGroup then
		playerGroup:UpdateTextures()
	end

	if petGroup then
		petGroup:UpdateTextures()
	end
end

---Runs the texture refresh once at the end of the frame however many times it is asked for in
---one, since LibSharedMedia fires once per registered entry and a media pack registers its
---whole set inside a single frame.
local function QueueTextureRefresh()
	if textureRefreshQueued then
		return
	end

	textureRefreshQueued = true

	C_Timer.After(0, function()
		textureRefreshQueued = false
		RefreshTextures()
	end)
end

---db.Texture holds a LibSharedMedia name, resolved live through Fetch, so both a texture pack
---registering late and a global statusbar override change what the bars should draw.
local function EnsureMediaSubscription()
	if mediaSubscribed then
		return
	end

	if not LSM or not LSM.RegisterCallback then
		return
	end

	mediaSubscribed = true

	LSM.RegisterCallback(addon, "LibSharedMedia_Registered", QueueTextureRefresh)
	LSM.RegisterCallback(addon, "LibSharedMedia_SetGlobal", QueueTextureRefresh)
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

local function GetClassColor(unit)
	local _, class = UnitClass(unit)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]

	if c then
		return c.r, c.g, c.b
	end
end

local function GetClassPowerColor(token, powerType)
	local cr, cg, cb = GetClassColor("player")

	if cr then
		return cr, cg, cb
	end

	local color = PowerBarColor and (PowerBarColor[POWER_TOKEN_BY_FIELD[token]] or PowerBarColor[powerType])

	if color and color.r and color.g and color.b then
		return color.r, color.g, color.b
	end

	return GetPowerColor()
end

---Mainline runes have no type of their own, so they take the tree colour of the spec
---that spends them.
local function GetRuneColor(runeType, specId)
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		local rgb = specId and RUNE_TYPE_COLORS[SPEC_RUNE_COLOR_INDEX[specId]]

		if rgb then
			return rgb[1], rgb[2], rgb[3]
		end

		local cr, cg, cb = GetClassColor("player")

		if cr then
			return cr, cg, cb
		end

		return GetPowerColor()
	end

	local rgb = runeType and RUNE_TYPE_COLORS[runeType]

	if rgb then
		return rgb[1], rgb[2], rgb[3]
	end

	return GetPowerColor()
end

-- A live client raises on an event name it doesn't know, so a name this addon added for a
-- flavour that might not have it goes through here instead of a bare RegisterEvent.
local function RegisterEventGuarded(frame, event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		if C_EventUtils.IsEventValid(event) then
			frame:RegisterEvent(event)
		end

		return
	end

	pcall(frame.RegisterEvent, frame, event)
end

-- Independent of ShowPower, so a player can hide the power bar and keep the pips.
local function ResolveClassPower()
	if not db.ClassPower.Enabled then
		return nil
	end

	local info = addon.ClassPower:Resolve()

	if not info or db.ClassPower.Show[info.Key] == false then
		return nil
	end

	return info
end

-- Creates a self-contained bar group for a WoW unit.
-- hasPower: whether this group includes a power bar (player=true, pet=false)
-- getPositionDb: function() → table with Point/RelativeTo/RelativePoint/X/Y/Locked
local function CreateBarGroup(unit, containerName, hasPower, getPositionDb)
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
				c:SetAlpha(c.TargetAlpha or 1)
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

	function group:FadeTo(show, targetAlpha)
		self:SetupFadeAnimations()

		local c = self.container
		targetAlpha = show and (targetAlpha or 1) or 0

		if c.IsShowing == show and (c.TargetAlpha or 1) == targetAlpha then
			return
		end

		c.IsShowing = show and true or false
		c.TargetAlpha = targetAlpha

		if show then
			if c.FadeOut and c.FadeOut:IsPlaying() then
				c.FadeOut:Stop()
			end

			if c.FadeIn and c.FadeIn.Alpha then
				c.FadeIn.Alpha:SetDuration(db.FadeInDuration or 1)
				c.FadeIn.Alpha:SetFromAlpha(c:GetAlpha())
				c.FadeIn.Alpha:SetToAlpha(targetAlpha)

				c.FadeIn:Stop()
				c.FadeIn:Play()
			else
				c:SetAlpha(targetAlpha)
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

		mini:ApplyPosition(self.container, pos)
		mini:SetPositionLocked(self.container, pos.Locked)
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
		local showClassPower = self.hasPower and ResolveClassPower() ~= nil
		local cpHeight = db.ClassPower.Height or 10

		local rows = 0
		local rowHeight = 0
		if showHealth then rows = rows + 1; rowHeight = rowHeight + h end
		if showPower then rows = rows + 1; rowHeight = rowHeight + h end
		if showClassPower then rows = rows + 1; rowHeight = rowHeight + cpHeight end

		-- Event handlers call this after a fade-out, so showing the container here would undo the fade.
		self.rowsEmpty = rows == 0

		if rows > 0 then
			local totalHeight = rowHeight + ((rows - 1) * gap) + pad * 2
			self.container:SetSize(w + pad * 2, totalHeight)
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

		if self.classPowerRow then
			self.classPowerRow:ClearAllPoints()
			self.classPowerRow:SetHeight(cpHeight)
			self.classPowerRow:SetShown(showClassPower)

			if showClassPower then
				local anchor = (showPower and self.powerBar) or (showHealth and self.healthBar)

				if anchor then
					self.classPowerRow:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
					self.classPowerRow:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
				else
					self.classPowerRow:SetPoint("TOPLEFT", self.container, "TOPLEFT", pad, -pad)
					self.classPowerRow:SetPoint("TOPRIGHT", self.container, "TOPRIGHT", -pad, -pad)
				end
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

		self:UpdateTickerVisibility()
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
				local fmt = db.HideTextSuffix and "%d" or "%d%%"
				self.healthText:SetText(string.format(fmt, pct))
			else
				local format = db.HealthTextFormat or "%s/%s"
				local current = db.HideTextSuffix and hp or AbbreviateNumbers(hp)
				local maximum = db.HideTextSuffix and max or AbbreviateNumbers(max)
				self.healthText:SetText(string.format(format, current, maximum))
			end
		end

		self:UpdateAbsorb()
	end

	function group:UpdateAbsorb()
		if not self.overshieldBar then
			return
		end

		-- Hide rather than skip updates entirely, as the incoming heal bar is
		-- updated in the same pass and should keep working with shields off
		local shieldsEnabled = not db.Shield or db.Shield.Enabled ~= false
		self.overshieldBar:SetShown(shieldsEnabled)
		if self.regularAbsorbBar then self.regularAbsorbBar:SetShown(shieldsEnabled) end
		if self.absorbZoneBgFrame then self.absorbZoneBgFrame:SetShown(shieldsEnabled) end

		local maxHealth = UnitHealthMax(self.unit) or 0
		local totalAbsorbs = UnitGetTotalAbsorbs(self.unit) or 0

		self.overshieldBar:SetMinMaxValues(0, maxHealth)

		if self.regularAbsorbBar then
			if self.healPredictionCalc and UnitGetDetailedHealPrediction then
				-- Midnight+: use calculator to avoid secret value arithmetic
				UnitGetDetailedHealPrediction(self.unit, nil, self.healPredictionCalc)
				local absorbAmount, clamped = self.healPredictionCalc:GetDamageAbsorbs()
				local missingHealth = self.healPredictionCalc:GetMissingHealth()
				self.regularAbsorbBar:SetMinMaxValues(0, missingHealth)
				self.regularAbsorbBar:SetValue(absorbAmount or 0)
				local overshieldOpacity = (db.Shield and db.Shield.Opacity) or 1
				self.regularAbsorbBar:SetAlphaFromBoolean(clamped, 0, overshieldOpacity)
				if self.absorbZoneBgFrame then self.absorbZoneBgFrame:SetAlphaFromBoolean(clamped, 0, 1) end
				self.overshieldBar:SetValue(totalAbsorbs)
				self.overshieldBar:SetAlphaFromBoolean(clamped, overshieldOpacity, 0)
				if self.incomingHealBar then
					local incomingAmount = self.healPredictionCalc:GetIncomingHeals()
					self.incomingHealBar:SetMinMaxValues(0, missingHealth)
					self.incomingHealBar:SetValue(incomingAmount)
				end
			else
				-- Legacy: values are non-secret numbers, direct math is safe
				local hp = UnitHealth(self.unit) or 0
				local remaining = math.max(0, maxHealth - hp)
				local cappedAbsorb = math.min(totalAbsorbs, remaining)
				local hasOvershield = totalAbsorbs > remaining
				self.regularAbsorbBar:SetMinMaxValues(0, remaining)
				self.regularAbsorbBar:SetValue(cappedAbsorb)
				local overshieldOpacity = (db.Shield and db.Shield.Opacity) or 1
				self.regularAbsorbBar:SetAlpha(hasOvershield and 0 or overshieldOpacity)
				if self.absorbZoneBgFrame then self.absorbZoneBgFrame:SetAlpha(hasOvershield and 0 or 1) end
				self.overshieldBar:SetValue(math.max(0, totalAbsorbs - remaining))
				self.overshieldBar:SetAlpha(hasOvershield and overshieldOpacity or 0)
				if self.incomingHealBar then
					local incomingHeals = UnitGetIncomingHeals and UnitGetIncomingHeals(self.unit) or 0
					self.incomingHealBar:SetMinMaxValues(0, remaining)
					self.incomingHealBar:SetValue(math.min(incomingHeals, remaining))
				end
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
				local fmt = db.HideTextSuffix and "%d" or "%d%%"
				self.powerText:SetText(string.format(fmt, pct))
			else
				local format = db.PowerTextFormat or "%s/%s"
				local current = db.HideTextSuffix and power or AbbreviateNumbers(power)
				local maximum = db.HideTextSuffix and max or AbbreviateNumbers(max)
				self.powerText:SetText(string.format(format, current, maximum))
			end
		end
	end

	function group:CreateClassPower()
		self.classPowerRow = CreateFrame("Frame", nil, self.container)
		self.classPowerRow:SetFrameLevel((self.container:GetFrameLevel() or 0) + 1)
		self.classPowerBoxes = {}
	end

	---Creates box i the first time it's needed, so the pool only ever grows to the largest
	---max this character has shown.
	function group:GetClassPowerBox(index)
		local box = self.classPowerBoxes[index]

		if box then
			return box
		end

		box = CreateFrame("StatusBar", nil, self.classPowerRow)
		box.Background = CreateBackground(box)
		box.Background:SetTexture(GetConfiguredTexture())
		box:SetStatusBarTexture(GetConfiguredTexture())

		local texture = box:GetStatusBarTexture()
		if texture then
			texture:SetHorizTile(false)
			texture:SetVertTile(false)
		end

		if db.Border then
			box.Outline = AddBlackOutline(box)
		end

		self.classPowerBoxes[index] = box

		return box
	end

	---The last box is also anchored to the row's right edge so rounding never leaves a ragged end.
	function group:LayoutClassPowerBoxes(n)
		local spacing = db.ClassPower.Spacing or 0
		local rowWidth = db.Width or 150
		local boxWidth = math.floor((rowWidth - (n - 1) * spacing) / n)

		for i = 1, n do
			local box = self:GetClassPowerBox(i)
			box:ClearAllPoints()
			box:SetHeight(db.ClassPower.Height or 10)

			if i == 1 then
				box:SetPoint("LEFT", self.classPowerRow, "LEFT", 0, 0)
			else
				box:SetPoint("LEFT", self.classPowerBoxes[i - 1], "RIGHT", spacing, 0)
			end

			if i == n then
				box:SetPoint("RIGHT", self.classPowerRow, "RIGHT", 0, 0)
			else
				box:SetWidth(boxWidth)
			end

			box:Show()
		end

		for i = n + 1, #self.classPowerBoxes do
			self.classPowerBoxes[i]:Hide()
		end
	end

	---Skipped when n hasn't moved since the last call, since this runs on every power tick.
	function group:LayoutClassPowerBoxesIfNeeded(n)
		if self.classPowerLayoutN == n then
			return
		end

		self:LayoutClassPowerBoxes(n)
		self.classPowerLayoutN = n
	end

	function group:UpdateClassPowerBoxesForPower(info)
		local current, max, mod = addon.ClassPower:ReadPower(info)
		local r, g, b = GetClassPowerColor(info.Token, info.PowerType)

		-- A secret max can't be divided into pips, so it's shown as a single bar spanning the
		-- row instead.
		if mini:IsSecret(max) then
			self:LayoutClassPowerBoxesIfNeeded(1)

			local box = self.classPowerBoxes[1]
			box:SetMinMaxValues(0, max)
			box:SetValue(current)
			SetBarColor(box, r, g, b)

			return
		end

		local n = max
		if type(n) ~= "number" or n < 1 then
			n = 1
		end

		self:LayoutClassPowerBoxesIfNeeded(n)

		for i = 1, n do
			local box = self.classPowerBoxes[i]
			box:SetMinMaxValues((i - 1) * mod, i * mod)
			box:SetValue(current)
			SetBarColor(box, r, g, b)
		end
	end

	---Only runs while a rune is recharging.
	function group:SetRuneUpdateEnabled(enabled)
		if enabled == self.runeUpdateEnabled then
			return
		end

		self.runeUpdateEnabled = enabled

		if enabled then
			self.runeUpdateElapsed = 0

			self.classPowerRow:SetScript("OnUpdate", function(_, elapsed)
				self.runeUpdateElapsed = self.runeUpdateElapsed + elapsed

				if self.runeUpdateElapsed < RUNE_UPDATE_INTERVAL then
					return
				end

				self.runeUpdateElapsed = 0
				self:UpdateClassPowerRunes()
			end)
		else
			self.classPowerRow:SetScript("OnUpdate", nil)
		end
	end

	function group:UpdateClassPowerRunes()
		self:LayoutClassPowerBoxesIfNeeded(6)

		local now = GetTime()

		-- Reused across calls because this runs ten times a second.
		if not self.runeStates then
			self.runeStates = {}
		end

		local runes = self.runeStates

		for i = 1, 6 do
			local start, duration, ready, runeType = addon.ClassPower:ReadRune(i)
			local state = runes[i]

			if not state then
				state = {}
				runes[i] = state
			end

			state.Ready = ready or not duration or duration <= 0
			state.Start = start
			state.Duration = duration
			state.Type = runeType
			state.Remaining = state.Ready and 0 or math.max(0, (start + duration) - now)
		end

		-- Mainline reads like Blizzard's own rune bar: ready runes first, then soonest ready.
		-- Classic pairs are positional, so their order is left alone.
		if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
			table.sort(runes, CompareRuneReadiness)
		end

		local anyRecharging = false
		local specId = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and addon.ClassPower:CurrentSpecId() or nil

		for slot = 1, 6 do
			local rune = runes[slot]
			local box = self.classPowerBoxes[slot]
			local r, g, b = GetRuneColor(rune.Type, specId)

			if rune.Ready then
				box:SetMinMaxValues(0, 1)
				box:SetValue(1)
			else
				box:SetMinMaxValues(0, rune.Duration)
				box:SetValue(now - rune.Start)
				anyRecharging = true
			end

			SetBarColor(box, r, g, b)
		end

		self:SetRuneUpdateEnabled(anyRecharging)
	end

	function group:UpdateClassPower()
		if not self.classPowerRow then
			return
		end

		local info = ResolveClassPower()
		local wasShown = self.classPowerRow:IsShown()

		-- Cached so UNIT_POWER_UPDATE/FREQUENT can filter its own token without resolving again
		-- on every tick. Runes refresh from RUNE_POWER_UPDATE/RUNE_TYPE_UPDATE instead.
		self.classPowerToken = info and info.Kind ~= "Runes" and info.Token or nil

		self.classPowerRow:SetShown(info ~= nil)

		if not info then
			self:SetRuneUpdateEnabled(false)
		elseif info.Kind == "Runes" then
			self:UpdateClassPowerRunes()
		else
			self:SetRuneUpdateEnabled(false)
			self:UpdateClassPowerBoxesForPower(info)
		end

		-- Row height doesn't depend on n, so only a shown-state change needs a resize.
		if (info ~= nil) ~= wasShown then
			self:UpdateSizes()
			self:UpdateVisibility()
		end
	end

	-- Renders the server's power regen tick. Classic-only: retail regen is continuous, so
	-- these frames are never created there and the option never appears.
	function group:CreateTicker()
		-- Parented to the power bar so it inherits its visibility, and one level above it so
		-- the marker draws over the fill but stays under the text frame.
		self.tickFrame = CreateFrame("Frame", nil, self.powerBar)
		self.tickFrame:SetAllPoints(self.powerBar)
		self.tickFrame:SetFrameLevel((self.powerBar:GetFrameLevel() or 0) + 1)
		self.tickFrame:Hide()

		-- Deliberately a flat, fully opaque block with no edging. The marker sweeps across both
		-- the filled bar and the dark empty part behind it, and anything that lets the
		-- background through - translucency, or an edge colour that only contrasts with one of
		-- them - makes it look like it changes as it crosses over. Legibility comes from the
		-- colour instead, which is why the default contrasts with both.
		self.tickSpark = self.tickFrame:CreateTexture(nil, "OVERLAY")
		self.tickSpark:Hide()

		-- Hiding the host frame stops the OnUpdate, so a disabled ticker - or a faded out
		-- bar group - costs nothing per frame.
		self.tickFrame:SetScript("OnUpdate", function()
			self:UpdateTicker()
		end)
	end

	function group:UpdateTicker()
		if not self.tickFrame then
			return
		end

		local ticker = db.Ticker
		local progress = addon.PowerTick:GetProgress()

		if not progress then
			-- Full power, a power type that doesn't tick, or the cadence isn't known yet -
			-- which covers the five second rule, since nothing arrives during it anyway.
			self.tickSpark:Hide()
			return
		end

		local color = ticker.Color
		local r = (color and color[1]) or 1
		local g = (color and color[2]) or 1
		local b = (color and color[3]) or 1
		local alpha = ticker.Opacity or 1

		-- This runs every frame the marker is visible, and SetColorTexture rebuilds the
		-- texture, so only write it when the configured colour has actually moved.
		if
			self.tickSparkR ~= r
			or self.tickSparkG ~= g
			or self.tickSparkB ~= b
			or self.tickSparkA ~= alpha
		then
			self.tickSparkR, self.tickSparkG, self.tickSparkB, self.tickSparkA = r, g, b, alpha
			self.tickSpark:SetColorTexture(r, g, b, alpha)
		end

		local width = self.tickFrame:GetWidth() or 0
		local thickness = ticker.Thickness or 2
		-- Centred on the boundary, then held inside the bar so it doesn't hang off either end.
		local offset = mini:ClampFloat(progress * width - thickness / 2, 0, math.max(0, width - thickness), 0)

		self.tickSpark:SetWidth(thickness)
		self.tickSpark:SetPoint("TOPLEFT", self.tickFrame, "TOPLEFT", offset, 0)
		self.tickSpark:SetPoint("BOTTOMLEFT", self.tickFrame, "BOTTOMLEFT", offset, 0)
		self.tickSpark:Show()
	end

	function group:UpdateTickerVisibility()
		if not self.tickFrame then
			return
		end

		local ticker = db.Ticker
		local enabled = (ticker and ticker.Enabled and db.ShowPower ~= false) and true or false

		-- The detector polls independently of this frame: it has to keep tracking the cadence
		-- while the marker is hidden, which it is at full power and through the five second rule.
		addon.PowerTick:SetEnabled(enabled)
		self.tickFrame:SetShown(enabled)

		if enabled then
			self:UpdateTicker()
		end
	end

	function group:UpdateColors()
		local hr, hg, hb

		if db.UseClassColorHealth then
			hr, hg, hb = GetClassColor(self.unit)
		end

		if not hr then
			hr = (db.HealthColor and db.HealthColor[1]) or 0
			hg = (db.HealthColor and db.HealthColor[2]) or 1
			hb = (db.HealthColor and db.HealthColor[3]) or 0
		end

		SetBarColor(self.healthBar, hr, hg, hb)

		if self.absorbZoneBg then
			self.absorbZoneBg:SetVertexColor(hr, hg, hb, 1)
		end

		local oc = db.Shield and db.Shield.Color
		local ocr = (oc and oc[1]) or 1
		local ocg = (oc and oc[2]) or 1
		local ocb = (oc and oc[3]) or 1

		if self.regularAbsorbBar then
			self.regularAbsorbBar:SetStatusBarColor(ocr, ocg, ocb, 1)
			if self.regularAbsorbBar.Background then
				self.regularAbsorbBar.Background:SetVertexColor(ocr, ocg, ocb, 1)
			end
		end

		if self.overshieldBar then
			self.overshieldBar:SetStatusBarColor(ocr, ocg, ocb, 1)
			if self.overshieldBar.Background then
				self.overshieldBar.Background:SetVertexColor(ocr, ocg, ocb, 1)
			end
		end

		if self.incomingHealBar then
			local ihc = db.IncomingHealColor
			self.incomingHealBar:SetStatusBarColor(
				(ihc and ihc[1]) or 0,
				(ihc and ihc[2]) or 1,
				(ihc and ihc[3]) or 0,
				1
			)
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

		if texture and self.incomingHealBar then
			self.incomingHealBar:SetStatusBarTexture(texture)
			local ihTex = self.incomingHealBar:GetStatusBarTexture()
			if ihTex then
				ihTex:SetHorizTile(false)
				ihTex:SetVertTile(false)
			end
		end

		if texture and self.regularAbsorbBar and self.regularAbsorbBar.Background then
			self.regularAbsorbBar.Background:SetTexture(texture)
		end

		if texture and self.overshieldBar and self.overshieldBar.Background then
			self.overshieldBar.Background:SetTexture(texture)
		end

		if texture and self.absorbZoneBg then
			self.absorbZoneBg:SetTexture(texture)
		end

		if self.classPowerBoxes then
			for _, box in ipairs(self.classPowerBoxes) do
				box:SetStatusBarTexture(texture)

				local boxTexture = box:GetStatusBarTexture()

				if boxTexture == nil then
					box:SetStatusBarTexture(fallbackTexture)
					boxTexture = box:GetStatusBarTexture()
				end

				if boxTexture then
					boxTexture:SetHorizTile(false)
					boxTexture:SetVertTile(false)
				end

				if texture and box.Background then
					box.Background:SetTexture(texture)
				end
			end
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

		if self.rowsEmpty then
			self.container:SetAlpha(0)
			self.container:Hide()
			self.container.IsShowing = false
			return
		end

		if db.AlwaysShow then
			local inCombat = UnitAffectingCombat("player")
			local targetAlpha = inCombat and 1 or (db.OutOfCombatOpacity or 1)
			self:FadeTo(true, targetAlpha)
			return
		end

		self:FadeTo(UnitAffectingCombat("player"))
	end

	function group:Load()
		self.container = CreateFrame("Frame", containerName, UIParent, "BackdropTemplate")

		mini:MakeMovable(self.container, getPositionDb(), {
			IsLocked = function()
				return getPositionDb().Locked and true or false
			end,
		})

		self.container:SetAlpha(0)
		self.container:Hide()

		self:SetupFadeAnimations()

		self.healthBar = CreateFrame("StatusBar", nil, self.container)
		self.healthBar.Background = CreateBackground(self.healthBar)

		-- Created before absorb zone frames so absorb zone renders on top within the same frame level
		self.incomingHealBar = CreateFrame("StatusBar", nil, self.container)
		self.incomingHealBar:SetStatusBarColor(0, 1, 0, 1)

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

			-- StatusBar wrapper so we can use SetAlphaFromBoolean to hide when an overshield is active
			self.absorbZoneBgFrame = CreateFrame("StatusBar", nil, self.container)
			self.absorbZoneBg = self.absorbZoneBgFrame:CreateTexture(nil, "ARTWORK")
			self.absorbZoneBg:SetPoint("TOPLEFT", self.absorbZoneBgFrame, "TOPLEFT", 0, 0)
			self.absorbZoneBg:SetPoint("BOTTOMRIGHT", regAbsTex, "BOTTOMRIGHT", 0, 0)
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
			self:CreateClassPower()
		end

		self:UpdateTextures()

		-- Anchor bars to the right edge of the health bar fill texture so they auto-track health changes.
		self.incomingHealBar:SetPoint("TOPLEFT", self.healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
		self.incomingHealBar:SetPoint("BOTTOMRIGHT", self.healthBar, "BOTTOMRIGHT", 0, 0)

		self.regularAbsorbBar:SetPoint("TOPLEFT", self.healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
		self.regularAbsorbBar:SetPoint("BOTTOMRIGHT", self.healthBar, "BOTTOMRIGHT", 0, 0)

		if self.absorbZoneBgFrame then
			self.absorbZoneBgFrame:SetPoint("TOPLEFT", self.healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
			self.absorbZoneBgFrame:SetPoint("BOTTOMRIGHT", self.healthBar, "BOTTOMRIGHT", 0, 0)
		end

		if CreateUnitHealPredictionCalculator then
			self.healPredictionCalc = CreateUnitHealPredictionCalculator()
			self.healPredictionCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
			if Enum.UnitIncomingHealClampMode then
				self.healPredictionCalc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
			end
		end

		local baseLevel = self.container:GetFrameLevel() or 0
		self.healthBar:SetFrameLevel(baseLevel + 1)
		if self.powerBar then self.powerBar:SetFrameLevel(baseLevel + 1) end
		if self.powerBar and addon.PowerTick:IsSupported() then self:CreateTicker() end
		self.incomingHealBar:SetFrameLevel(baseLevel + 1)
		if self.absorbZoneBgFrame then self.absorbZoneBgFrame:SetFrameLevel(baseLevel + 1) end
		-- Shield bars above so they render on top of the incoming heal bar and absorb zone backing
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
		-- A settings change can move Width, Spacing or the class power Height without changing
		-- the box count, so the cache that skips re-layout on an unchanged count can't be trusted here.
		self.classPowerLayoutN = nil

		self:ApplyPosition()
		self:UpdateSizes()
		self:UpdateColors()
		self:UpdateVisibility()
		self:UpdateHealth()
		self:UpdateAbsorb()
		self:UpdatePower()
		self:UpdateClassPower()
		self:UpdateTextures()
		self:UpdateFonts()
	end

	return group
end

local function Load()
	playerGroup = CreateBarGroup("player", addonName .. "Frame", true, function() return db end)
	playerGroup:Load()

	petGroup = CreateBarGroup("pet", addonName .. "PetFrame", false, function() return db.Pet end)
	petGroup:Load()

	addon:Reload()
end

local function OnEvent(_, event, arg1, arg2)
	if event == "PLAYER_ENTERING_WORLD" then
		-- A zone change can put an arbitrary gap between the last observed tick and the next,
		-- so the cadence has to restart from scratch.
		addon.PowerTick:Reset()
		playerGroup:UpdateHealth()
		playerGroup:UpdateAbsorb()
		playerGroup:UpdatePower()
		playerGroup:UpdateSizes()
		playerGroup:UpdateClassPower()
		playerGroup:UpdateVisibility()
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

	if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
		if arg1 == "player" then
			playerGroup:UpdatePower()

			if db.ClassPower.Enabled and arg2 == POWER_TOKEN_BY_FIELD[playerGroup.classPowerToken] then
				playerGroup:UpdateClassPower()
			end
		end
		return
	end

	if event == "UNIT_DISPLAYPOWER" then
		if arg1 == "player" then
			playerGroup:UpdatePower()
			playerGroup:UpdateSizes()
			playerGroup:UpdateVisibility()
			playerGroup:UpdateClassPower()
		end
		return
	end

	if event == "UNIT_MAXPOWER" then
		if arg1 == "player" then
			playerGroup:UpdateSizes()
			playerGroup:UpdateVisibility()
			playerGroup:UpdateClassPower()
		end
		return
	end

	if event == "PLAYER_SPECIALIZATION_CHANGED" then
		if arg1 == "player" then
			playerGroup:UpdateSizes()
			playerGroup:UpdateVisibility()
			playerGroup:UpdateClassPower()
		end
		return
	end

	if event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE" then
		playerGroup:UpdateClassPower()
		return
	end

	if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_COMBO_POINTS" then
		playerGroup:UpdateClassPower()
		return
	end

	if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
	or event == "UNIT_HEAL_PREDICTION" then
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

	EnsureMediaSubscription()

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
				eventsFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
				eventsFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player", "pet")
				eventsFrame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player", "pet")
				eventsFrame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", "player", "pet")
			else
				eventsFrame:RegisterEvent("UNIT_HEALTH")
				eventsFrame:RegisterEvent("UNIT_POWER_UPDATE")
				eventsFrame:RegisterEvent("UNIT_POWER_FREQUENT")
				eventsFrame:RegisterEvent("UNIT_DISPLAYPOWER")
				eventsFrame:RegisterEvent("UNIT_MAXPOWER")
				eventsFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
				eventsFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
				eventsFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
			end

			RegisterEventGuarded(eventsFrame, "PLAYER_SPECIALIZATION_CHANGED")
			RegisterEventGuarded(eventsFrame, "RUNE_POWER_UPDATE")
			RegisterEventGuarded(eventsFrame, "RUNE_TYPE_UPDATE")

			if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
				eventsFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

				-- Wrath and Cata Classic can still fire this legacy event for a same-target
				-- combo point change, alongside or instead of UNIT_POWER_UPDATE.
				RegisterEventGuarded(eventsFrame, "UNIT_COMBO_POINTS")
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

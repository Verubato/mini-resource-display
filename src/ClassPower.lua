local _, addon = ...
local mini = addon.Framework

---@class ClassPowerCandidate
---@field Class string
---@field PowerType string Enum.PowerType field name, resolved at call time
---@field Kind "Power"|"Runes"?
---@field SpecId number? required spec, when the resource only applies to one
---@field DisplayPowerToken string? required UnitPowerType token, for a class with more than one

-- Mists has chi on every spec, and embers and orbs exist only there.
local MAINLINE = {
	UsesSpec = true,
	Candidates = {
		{ Class = "ROGUE", PowerType = "ComboPoints" },
		{ Class = "DRUID", PowerType = "ComboPoints", DisplayPowerToken = "ENERGY" },
		{ Class = "PALADIN", PowerType = "HolyPower" },
		{ Class = "MONK", PowerType = "Chi", SpecId = 269 },
		{ Class = "WARLOCK", PowerType = "SoulShards" },
		{ Class = "MAGE", PowerType = "ArcaneCharges", SpecId = 62 },
		{ Class = "EVOKER", PowerType = "Essence" },
		{ Class = "DEATHKNIGHT", PowerType = "Runes", Kind = "Runes" },
	},
}

local MISTS = {
	UsesSpec = true,
	Candidates = {
		{ Class = "ROGUE", PowerType = "ComboPoints" },
		{ Class = "DRUID", PowerType = "ComboPoints", DisplayPowerToken = "ENERGY" },
		{ Class = "PALADIN", PowerType = "HolyPower" },
		{ Class = "MONK", PowerType = "Chi" },
		{ Class = "WARLOCK", PowerType = "SoulShards", SpecId = 265 },
		{ Class = "WARLOCK", PowerType = "BurningEmbers", SpecId = 267 },
		{ Class = "PRIEST", PowerType = "ShadowOrbs", SpecId = 258 },
		{ Class = "DEATHKNIGHT", PowerType = "Runes", Kind = "Runes" },
	},
}

-- No spec API here. The enum and max guards in Resolve keep holy power and shards off clients
-- too old for them.
local OTHER_CLASSIC = {
	UsesSpec = false,
	Candidates = {
		{ Class = "ROGUE", PowerType = "ComboPoints" },
		{ Class = "DRUID", PowerType = "ComboPoints", DisplayPowerToken = "ENERGY" },
		{ Class = "PALADIN", PowerType = "HolyPower" },
		{ Class = "WARLOCK", PowerType = "SoulShards" },
		{ Class = "DEATHKNIGHT", PowerType = "Runes", Kind = "Runes" },
	},
}

---@class ClassPower
local M = {}

addon.ClassPower = M

---Picks the flavour's candidate list at call time rather than at load, so a test can switch
---WOW_PROJECT_ID and get a different table on the next call.
local function ActiveFlavor()
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		return MAINLINE
	end

	if WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC then
		return MISTS
	end

	return OTHER_CLASSIC
end

---@return number?
local function GetSpecIndex()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end

	if GetSpecialization then
		return GetSpecialization()
	end

	return nil
end

---@param specIndex number?
---@return number?
local function GetSpecId(specIndex)
	if not specIndex then
		return nil
	end

	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		return (C_SpecializationInfo.GetSpecializationInfo(specIndex))
	end

	if GetSpecializationInfo then
		return (GetSpecializationInfo(specIndex))
	end

	return nil
end

---@return string? token the player's own display power, e.g. "ENERGY"
local function GetDisplayPowerToken()
	return (select(2, UnitPowerType("player")))
end

---@param flavor table
---@param classToken string
---@param specId number? when given, a candidate restricted to another spec doesn't count
---@return boolean
local function HasCandidate(flavor, classToken, specId)
	for _, candidate in ipairs(flavor.Candidates) do
		if candidate.Class == classToken and (not candidate.SpecId or candidate.SpecId == specId) then
			return true
		end
	end

	return false
end

---@param candidate ClassPowerCandidate
---@param powerType number?
---@param maxPower number|boolean|nil
---@return boolean
local function HasResource(candidate, powerType, maxPower)
	-- Classic clients report no rune max, so the rune API is the only sign runes exist.
	if candidate.Kind == "Runes" then
		return type(GetRuneCooldown) == "function"
	end

	-- A secret max can't be compared, but it stands for some positive amount or the
	-- client wouldn't have minted one at all.
	return powerType ~= nil and (mini:IsSecret(maxPower) or (maxPower or 0) > 0)
end

---@return number? specId the player's current spec, for callers outside Resolve that need it
function M:CurrentSpecId()
	return GetSpecId(GetSpecIndex())
end

---@return nil|{ Key: number|string, Kind: "Power"|"Runes", PowerType: number, Token: string }
function M:Resolve()
	local _, classToken = UnitClass("player")

	if not classToken then
		return nil
	end

	local flavor = ActiveFlavor()
	local specId = GetSpecId(GetSpecIndex())

	-- No spec chosen yet means no key to show or hide the row by.
	if flavor.UsesSpec and not specId then
		return nil
	end

	for _, candidate in ipairs(flavor.Candidates) do
		if
			candidate.Class == classToken
			and (not candidate.SpecId or candidate.SpecId == specId)
			and (not candidate.DisplayPowerToken or candidate.DisplayPowerToken == GetDisplayPowerToken())
		then
			local powerType = Enum and Enum.PowerType and Enum.PowerType[candidate.PowerType]
			local maxPower = powerType ~= nil and UnitPowerMax("player", powerType)

			if HasResource(candidate, powerType, maxPower) then
				return {
					Key = (flavor.UsesSpec and specId) or classToken,
					Kind = candidate.Kind or "Power",
					PowerType = powerType,
					Token = candidate.PowerType,
				}
			end
		end
	end

	return nil
end

---@param info table returned by Resolve
---@return number current, number max, number mod
function M:ReadPower(info)
	local current

	-- Classic combo points live on the target rather than the player, and only GetComboPoints
	-- exposes them there.
	if
		info.Token == "ComboPoints"
		and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
		and type(GetComboPoints) == "function"
	then
		current = GetComboPoints("player", "target")
	else
		current = UnitPower("player", info.PowerType, true)
	end

	local max = UnitPowerMax("player", info.PowerType) or 0
	local mod = 1

	if type(UnitPowerDisplayMod) == "function" then
		local candidate = UnitPowerDisplayMod(info.PowerType)

		if type(candidate) == "number" and candidate >= 1 then
			mod = candidate
		end
	end

	return current, max, mod
end

---@param index number rune slot, 1 to 6
---@return number start, number duration, boolean ready, number? runeType
function M:ReadRune(index)
	local start, duration, ready = GetRuneCooldown(index)
	local runeType

	if type(GetRuneType) == "function" then
		runeType = GetRuneType(index)
	end

	return start, duration, ready, runeType
end

---Every key across all three flavours, not just the current class, because dbDefaults is one
---shared table built once before any character's class is known.
---@return table<number|string, boolean>
function M:DefaultShow()
	local show = {}

	for _, flavor in ipairs({ MAINLINE, MISTS, OTHER_CLASSIC }) do
		for _, candidate in ipairs(flavor.Candidates) do
			show[candidate.SpecId or candidate.Class] = true
		end
	end

	return show
end

---{ Key, Label } rows for the player's own class on this client, for the settings panel.
---@return { Key: number|string, Label: string }[]
function M:VisibilityEntries()
	local _, classToken, classId = UnitClass("player")

	if not classToken then
		return {}
	end

	local flavor = ActiveFlavor()

	if not flavor.UsesSpec then
		if not HasCandidate(flavor, classToken) then
			return {}
		end

		local label = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken

		return { { Key = classToken, Label = label } }
	end

	if not classId or not GetSpecializationInfoForClassID or not GetNumSpecializationsForClassID then
		return {}
	end

	local entries = {}
	local numSpecs = GetNumSpecializationsForClassID(classId) or 0

	for i = 1, numSpecs do
		local specId, name = GetSpecializationInfoForClassID(classId, i)

		if specId and HasCandidate(flavor, classToken, specId) then
			entries[#entries + 1] = { Key = specId, Label = name }
		end
	end

	return entries
end

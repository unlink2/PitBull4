
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local EXAMPLE_VALUE = 0.6

local PitBull4_ThreatBar = PitBull4:NewModule("ThreatBar")

PitBull4_ThreatBar:SetModuleType("bar")
PitBull4_ThreatBar:SetName(L["Threat bar"])
PitBull4_ThreatBar:SetDescription(L["Show a threat bar."])
PitBull4_ThreatBar:SetDefaults({
	size = 1,
	position = 5,
	show_solo = false,
},{
	threat_colors = {
		[0] = {0.69, 0.69, 0.69}, -- not tanking, lower threat than tank
		[1] = {1, 1, 0.47},       -- not tanking, higher threat than tank
		[2] = {1, 0.6, 0},        -- insecurely tanking, another unit has higher threat
		[3] = {1, 0, 0},          -- securely tanking, highest threat
	},
})

function PitBull4_ThreatBar:OnEnable()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateAll")
	self:RegisterEvent("UNIT_THREAT_LIST_UPDATE", "UpdateAll")
	self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", "UpdateAll")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("UNIT_PET")

	self:GROUP_ROSTER_UPDATE()
end

local player_in_group = false

local ACCEPTABLE_CLASSIFICATIONS = {
	player = true,
	pet = true,
	party = true,
	raid = true,
	partypet = true,
	raidpet = true,
}

local function check_classification(frame)
	local classification = frame.is_singleton and frame.unit or frame.header.unit_group
	return ACCEPTABLE_CLASSIFICATIONS[classification]
end

function PitBull4_ThreatBar:GROUP_ROSTER_UPDATE()
	player_in_group = UnitExists("pet") or IsInGroup()

	self:UpdateAll()
end

function PitBull4_ThreatBar:UNIT_PET(_, unit)
	if unit == "player" then
		self:GROUP_ROSTER_UPDATE()
	end
end

function PitBull4_ThreatBar:GetValue(frame)
	if not check_classification(frame) or (not self:GetLayoutDB(frame).show_solo and not player_in_group) then
		return nil
	end

	local _, _, scaled_percent = UnitDetailedThreatSituation(frame.unit, "target")
	if not scaled_percent then
		return nil
	end
	return scaled_percent / 100
end
function PitBull4_ThreatBar:GetExampleValue(frame)
	if frame and not check_classification(frame) then
		return nil
	end
	return EXAMPLE_VALUE
end

function PitBull4_ThreatBar:GetColor(frame, value)
	if frame.guid then
		local _, status = UnitDetailedThreatSituation(frame.unit, "target")
		if status then
			return unpack(self.db.profile.global.threat_colors[status])
		end
	end
	return unpack(self.db.profile.global.threat_colors[0])
end
function PitBull4_ThreatBar:GetExampleColor(frame, value)
	return unpack(self.db.profile.global.threat_colors[0])
end

PitBull4_ThreatBar:SetLayoutOptionsFunction(function(self)
	return "show_solo", {
		name = L["Show when solo"],
		desc = L["Show the threat bar even if you not in a group."],
		type = "toggle",
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).show_solo
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).show_solo = value
			PitBull4.Options.UpdateFrames()
		end,
	}
end)

PitBull4_ThreatBar:SetColorOptionsFunction(function(self)
	local function get(info)
		return unpack(self.db.profile.global.threat_colors[info.arg])
	end
	local function set(info, r, g, b, a)
		self.db.profile.global.threat_colors[info.arg] = {r, g, b, a}
		self:UpdateAll()
	end
	return 'threat_0_color', {
		type = "color",
		name = L["Not tanking, lower threat than tank"],
		arg = 0,
		get = get,
		set = set,
		width = "full",
	},
	'threat_1_color', {
		type = 'color',
		name = L["Not tanking, higher threat than tank"],
		arg = 1,
		get = get,
		set = set,
		width = "full",
	},
	'threat_2_color', {
		type = "color",
		name = L["Insecurely tanking, not highest threat"],
		arg = 2,
		get = get,
		set = set,
		width = "full",
	},
	'threat_3_color', {
		type = "color",
		name = L["Securely tanking, highest threat"],
		arg = 3,
		get = get,
		set = set,
		width = "full",
	},
	function(info)
		local threat_colors = self.db.profile.global.threat_colors
		threat_colors[0] = {0.69, 0.69, 0.69}
		threat_colors[1] = {1, 1, 0.47}
		threat_colors[2] = {1, 0.6, 0}
		threat_colors[3] = {1, 0, 0}
	end
end)

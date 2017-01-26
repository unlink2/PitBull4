-- Aura.lua : Core setup of the Aura module and event processing

local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_Aura = PitBull4:NewModule("Aura", "AceEvent-3.0")

local MSQ = LibStub("Masque", true)

PitBull4_Aura:SetModuleType("custom")
PitBull4_Aura:SetName(L["Aura"])
PitBull4_Aura:SetDescription(L["Shows buffs and debuffs for PitBull4 frames."])

-- constants for slot ids
PitBull4_Aura.MAINHAND = GetInventorySlotInfo("MainHandSlot")
PitBull4_Aura.OFFHAND = GetInventorySlotInfo("SecondaryHandSlot")

PitBull4_Aura.OnProfileChanged_funcs = {}

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timer = 0
local elapsed_since_text_update = 0
timerFrame:SetScript("OnUpdate",function(self, elapsed)
	timer = timer + elapsed
	if timer >= 0.2 then
		PitBull4_Aura:OnUpdate()
		timer = 0
	end

	local next_text_update = PitBull4_Aura.next_text_update
	if next_text_update then
		next_text_update = next_text_update - elapsed
		elapsed_since_text_update = elapsed_since_text_update + elapsed
		if next_text_update <= 0 then
			next_text_update = PitBull4_Aura:UpdateCooldownTexts(elapsed_since_text_update)
			elapsed_since_text_update = 0
		end
		PitBull4_Aura.next_text_update = next_text_update
	end
end)


function PitBull4_Aura:OnEnable()
	self:RegisterEvent("UNIT_AURA")
	timerFrame:Show()

	-- Need to track spec changes since it can change what they can dispel.
	local _,player_class = UnitClass("player")
	if player_class == "DRUID" or player_class == "MONK" or player_class == "PALADIN" or player_class == "PRIEST" or player_class == "SHAMAN" then
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		self:RegisterEvent("SPELLS_CHANGED", "PLAYER_TALENT_UPDATE")
		self:PLAYER_TALENT_UPDATE()
	end

	if MSQ then
		-- Pre-populate the Masque groups so they're all available in
		-- options without opening the config/going into config mode.
		for layout_name in next, PitBull4.db.profile.layouts do
			MSQ:Group("PitBull4 Aura", layout_name)
		end
	end
end

function PitBull4_Aura:OnDisable()
	timerFrame:Hide()
end

function PitBull4_Aura:OnProfileChanged()
	local funcs = self.OnProfileChanged_funcs
	for i = 1, #funcs do
		funcs[i](self)
	end
	LibStub("AceConfigRegistry-3.0"):NotifyChange("PitBull4")
end

function PitBull4_Aura:ClearFrame(frame)
	self:ClearAuras(frame)
	if frame.aura_highlight then
		frame.aura_highlight = frame.aura_highlight:Delete()
	end
end

PitBull4_Aura.OnHide = PitBull4_Aura.ClearFrame

function PitBull4_Aura:UpdateFrame(frame)
	if MSQ then
		-- if the layout changed, remove the auras from the old group
		if frame.masque_group and frame.masque_group.Group ~= frame.layout then
			self:ClearAuras(frame)
			frame.masque_group = nil
		end
		if not frame.masque_group then
			frame.masque_group = MSQ:Group("PitBull4 Aura", frame.layout)
		end
	end
	self:UpdateAuras(frame)
	self:LayoutAuras(frame)
end

function PitBull4_Aura:LibSharedMedia_Registered(event, mediatype, key)
	if mediatype == "font" then
		self:UpdateAll()
	end
end

-- Update.lua : Code to collect the auras on a unit, create the
-- aura frames and set the data to display the auras.

local PitBull4 = _G.PitBull4
local L = PitBull4.L
local PitBull4_Aura = PitBull4:GetModule("Aura")

local UnitAura = _G.UnitAura
local GetWeaponEnchantInfo = _G.GetWeaponEnchantInfo
local ceil = _G.math.ceil
local GetTime = _G.GetTime
local unpack = _G.unpack
local sort = _G.table.sort
local wipe = _G.table.wipe

-- The table we use for gathering the aura data, filtering
-- and then sorting them.  This table is reused without
-- wiping it ever, so care must be taken to use it in ways
-- that don't break this optimization.
--
-- The table consists of indexed entries of other tables.
-- These tables contains a list of values that are returned
-- from UnitAura or in the case of other sources of auras
-- generated by PitBull.  PitBull's own extra values must
-- be in the positions ahead of those used by UnitAura() otherwise
-- any new returns from UnitAura will break the module.
--
-- The entry values are as follows
-- [1] = index used to get the Aura with UnitAura or 0 for non UnitAura entries
-- [2] = slot of the weapon enchant or nil if not a weapon enchant
-- [3] = quality of the weapon or nil if not a weapon enchant
-- [4] = is_buff
-- [5] = name
-- [6] = rank
-- [7] = icon
-- [8] = count
-- [9] = debuff_type
-- [10] = duration
-- [11] = expiration_time
-- [12] = caster
-- [13] = is_stealable
-- [14] = nameplate_show_personal
-- [15] = spell_id
-- [16] = can_apply_aura
-- [17] = boss_debuff
-- [18] = cast_by_player
-- [19] = nameplate_show_all
-- [20] = time_mod

local list = {}

-- pool of available entries to be used in list
local pool = {}

-- The final index of the entries.  We need this so we can always
-- get all values when copying or using unpack.
local ENTRY_END = 20

-- Table we store the weapon enchant info in.
-- This table is never cleared and entries are reused.
-- The entry tables follow the same format as those used for the aura
-- list.  Since they are simply copied into that list.  To avoid
-- GC'ing entries constantly when there is no MH or OH enchant the
-- index 2 (the slot value) is set to nil.
local weapon_list = {}

-- cache for weapon enchant durations
-- contains the name of the enchant and the value of the duration
local weapon_durations = {}

-- constants for the slot ids
local INVSLOT_MAINHAND = _G.INVSLOT_MAINHAND
local INVSLOT_OFFHAND = _G.INVSLOT_OFFHAND

-- constants for building sample auras
local sample_buff_icon   = [[Interface\Icons\Spell_ChargePositive]]
local sample_debuff_icon = [[Interface\Icons\Spell_ChargeNegative]]
local sample_debuff_types = { 'Poison', 'Magic', 'Disease', 'Curse', 'Enrage', 'nil', }

-- constants for formating time
local HOUR_ONELETTER_ABBR = _G.HOUR_ONELETTER_ABBR:gsub("%s", "") -- "%dh"
local MINUTE_ONELETTER_ABBR = _G.MINUTE_ONELETTER_ABBR:gsub("%s", "") -- "%dm"

-- units to consider mine
local my_units = {
	player = true,
	pet = true,
	vehicle = true,
}


-- table of dispel types we can dispel
local can_dispel = PitBull4_Aura.can_dispel.player

local function new_entry()
	local t = next(pool)
	if t then
		pool[t] = nil
	else
		t = {}
	end
	return t
end

local function del_entry(t)
	wipe(t)
	pool[t] = true
	return nil
end

-- Fills an array of arrays with the information about the auras
local function get_aura_list(list, unit, db, is_buff, frame)
	if not unit then return end
	local filter = is_buff and "HELPFUL" or "HARMFUL"
	local id = 1
	local index = 1

	-- Loop through the auras
	while true do
		local entry = list[index]
		if not entry then
			entry = new_entry()
			list[index] = entry
		end

		-- Note entry[2] says if the aura is a weapon enchant
		-- entry[6] (rank text) was removed in 8.0
		entry[1], entry[2], entry[3], entry[4], entry[5],
			entry[7], entry[8], entry[9], entry[10], entry[11],
			entry[12], entry[13], entry[14], entry[15], entry[16],
			entry[17], entry[18], entry[19], entry[20] =
			id, nil, nil, is_buff, UnitAura(unit, id, filter)

		if not entry[5] then
			-- No more auras, break the outer loop
			break
		end

		-- Hack to get around a Blizzard bug.  The Enrage debuff_type
		-- gets set to "" instead of "Enrage" like it should.
		-- Once this is fixed this code should be removed.
		if entry[9] == "" then
			entry[9] = "Enrage"
		end

		-- Pass the entry through to the Highlight system
		if db.highlight then
			PitBull4_Aura:HighlightFilter(db, entry, frame)
		end

		-- Filter the list if not true
		local pb4_filter_name = is_buff and db.layout.buff.filter or db.layout.debuff.filter
		if PitBull4_Aura:FilterEntry(pb4_filter_name, entry, frame) then
			-- Reuse this index position if the aura was
			-- filtered.
			index = index + 1
		end

		id = id + 1

	end

	-- Clear the list of extra entries
	for i = index, #list do
		list[i] = del_entry(list[i])
	end

	return list
end

-- Fills up to the maximum number of auras with sample auras
local function get_aura_list_sample(list, unit, max, db, is_buff, is_player)
	-- figure the slot to use for the mainhand and offhand slots
	local mainhand, offhand
	if is_buff and db.enabled_weapons and unit and is_player then
		local mh, oh = weapon_list[INVSLOT_MAINHAND], weapon_list[INVSLOT_OFFHAND]
		if not mh or not mh[2] then
			mainhand = #list + 1
		end
		if not oh or not oh[2] then
			offhand = (mainhand and mainhand + 1) or #list + 1
		end
	end

	local num_entries = #list
	for i = num_entries + 1, max do
		local entry = list[i]
		if not entry then
			entry = new_entry()
			list[i] = entry
		end


		-- Create our bogus aura entry
		entry[1]  = 0 -- index 0 means PitBull generated aura
		if i == mainhand then
			entry[2] = INVSLOT_MAINHAND
			local link = GetInventoryItemLink("player", INVSLOT_MAINHAND)
			entry[3] = link and select(3,GetItemInfo(link)) or 4 -- quality or epic if no item
			entry[5] = L["Sample Weapon Enchant"] -- name
			entry[9] = nil -- no debuff type
			entry[12] = "player" -- treat weapon enchants as yours
		elseif i == offhand then
			entry[2] = INVSLOT_OFFHAND
			local link = GetInventoryItemLink("player", INVSLOT_OFFHAND)
			entry[3] = link and select(3,GetItemInfo(link)) or 4 -- quality or epic if no item
			entry[5] = L["Sample Weapon Enchant"] -- name
			entry[9] = nil -- no debuff type
			entry[12] = "player" -- treat weapon enchants as yours
		else
			entry[2]  = nil -- not a weapon enchant
			entry[3]  = nil -- no quality color
			entry[5]  = is_buff and L["Sample Buff"] or L["Sample Debuff"] -- name
			entry[9]  = sample_debuff_types[(i-1)% #sample_debuff_types]
			entry[12]  = (i - num_entries < 5) and "player" or nil -- caster (show 4 player entries)
		end
		entry[4]  = is_buff
		entry[6]  = nil -- rank
		entry[7]  = is_buff and sample_buff_icon or sample_debuff_icon
		entry[8]  = i -- count set to index to make order show
		entry[10]  = 0 -- duration
		entry[11]  = 0 -- expiration_time
		entry[13] = nil -- is_stealable
		entry[14] = nil -- nameplate_show_personal
		entry[15] = nil -- spell_id
		entry[16] = nil -- can_apply_aura
		entry[17] = nil -- boss_debuff
		entry[18] = nil -- cast_by_player
		entry[19] = nil -- nameplate_show_all
		entry[20] = 0 -- time_mod
	end
end

-- Get the name of the temporary enchant on a weapon from the tooltip
-- given the item slot the weapon is in.
local get_weapon_enchant_name
do
	local tt = CreateFrame("GameTooltip", "PitBull4_Aura_Tooltip", UIParent)
	tt:SetOwner(UIParent, "ANCHOR_NONE")
	local left = {}

	local g = tt:CreateFontString()
	g:SetFontObject(_G.GameFontNormal)
	for i = 1, 30 do
		local f = tt:CreateFontString()
		f:SetFontObject(_G.GameFontNormal)
		tt:AddFontStrings(f, g)
		left[i] = f
	end

	get_weapon_enchant_name = function(slot)
		tt:ClearLines()
		if not tt:IsOwned(UIParent) then
			tt:SetOwner(UIParent, "ANCHOR_NONE")
		end
		tt:SetInventoryItem("player", slot)

		for i = 1, 30 do
			local text = left[i]:GetText()
			if text then
				local buff_name = text:match("^(.+) %(%d+ [^$)]+%)$")
				if buff_name then
					local buff_name_no_rank = buff_name:match("^(.*) %d+$")
					return buff_name_no_rank or buff_name
				end
			else
				break
			end
		end
	end
end

-- Takes the data for a weapon enchant and builds an aura entry
local function set_weapon_entry(list, is_enchant, time_left, expiration_time, count, slot)
	local entry = list[slot]
	if not entry then
		entry = {}
		list[slot] = entry
	end

	-- No such enchant, clear the table
	if not is_enchant then
		wipe(entry)
		return
	end

	local weapon, _, quality, _, _, _, _, _, _, texture = GetItemInfo(GetInventoryItemLink("player", slot))
	-- Try and get the name of the enchant from the tooltip, if not
	-- use the weapon name.
	local name = get_weapon_enchant_name(slot) or weapon

	-- name should always have gotten set by the above but per ticket 418 it apparently
	-- can sometimes not get set.  Probably due the cache being empty.  It's ok to end
	-- up doing nothing because eventually it should work and the weapon enchants are
	-- checked on a timer anyway.
	if not name then
		wipe(entry)
		return
	end

	-- Figure the duration by keeping track of the longest
	-- time_left we've seen.
	local duration = weapon_durations[name]
	time_left = ceil(time_left / 1000)
	if not duration or duration < time_left then
		duration = time_left
		weapon_durations[name] = duration
	end

	entry[1] = 0 -- index 0 means PitBull generated aura
	-- If there's no enchant set we set entry[2] to nil
	entry[2] = slot -- a weapon enchant
	entry[3] = quality
	entry[4] = true -- is_buff
	entry[5] = name
	entry[6] = nil -- rank
	entry[7] = texture
	entry[8] = count
	entry[9] = nil
	entry[10] = duration
	entry[11] = expiration_time
	entry[12] = "player" -- treat weapon enchants as always yours
	entry[13] = nil -- is_stealable
	entry[14] = nil -- nameplate_show_personal
	entry[15] = nil -- spell_id
	entry[16] = nil -- can_apply_aura
	entry[17] = nil -- boss_debuff
	entry[18] = nil -- cast_by_player
	entry[19] = nil -- nameplate_show_all
	entry[20] = 0 -- time_mod
end

-- If the src table has a valid weapon enchant entry for the slot
-- copy it to the dst table.  Uses #dst + 1 to determine next entry
local function copy_weapon_entry(src, dst, slot)
	local src_entry = src[slot]
	-- If there's no src_entry or the slot value of the src_entry
	-- is empty don't copy anything.
	if not src_entry or not src_entry[2] then return end
	local i = #dst + 1
	local dst_entry = dst[i]
	if not dst_entry then
		dst_entry = new_entry()
		dst[i] = dst_entry
	end

	for pos = 1, ENTRY_END do
		dst_entry[pos] = src_entry[pos]
	end
end

local aura_sort__is_friend
local aura_sort__is_buff

local function aura_sort(a, b)
	if not a then
		return false
	elseif not b then
		return true
	end

	-- item buffs first
	local a_slot, b_slot = a[2], b[2]
	if a_slot and not b_slot then
		return true
	elseif not a_slot and b_slot then
		return false
	elseif a_slot and b_slot then
		return a_slot < b_slot
	end

	-- show your own auras first
	local a_mine, b_mine=  my_units[a[12]], my_units[b[12]]
	if a_mine~= b_mine then
		if a_mine then
			return true
		elseif b_mine then
			return false
		end
	end

	--  sort by debuff type
	if (aura_sort__is_buff and not aura_sort__is_friend) or (not aura_sort__is_buff and aura_sort__is_friend) then
		local a_debuff_type, b_debuff_type = a[9], b[9]
		if a_debuff_type ~= b_debuff_type then
			if not a_debuff_type then
				return false
			elseif not b_debuff_type then
				return true
			end
			local a_can_dispel = can_dispel[a_debuff_type]
			if (not a_can_dispel) ~= (not can_dispel[b_debuff_type]) then
				-- show debuffs you can dispel first
				if a_can_dispel then
					return true
				else
					return false
				end
			end
			return a_debuff_type < b_debuff_type
		end
	end

	-- sort real auras before samples
	local a_id, b_id = a[1], b[1]
	if a_id ~= 0 and b_id == 0 then
		return true
	elseif a_id == 0 and b_id ~= 0 then
		return false
	end

	-- sort by name
	local a_name, b_name = a[5], b[5]
	if a_name ~= b_name then
		if not a_name then
			return true
		elseif not b_name then
			return false
		end
		-- TODO: Add sort by ones we can cast
		return a_name < b_name
	end

	-- Use count for sample ids to preserve ID order.
	if a_id == 0 and b_id == 0 then
		local a_count, b_count = a[8], b[8]
		if not a_count then
			return false
		elseif not b_count then
			return true
		end
		return a_count < b_count
	end

	-- keep ID order
	if not a_id then
		return false
	elseif not b_id then
		return true
	end
	return a_id < b_id
end

-- Setups up the aura frame and fill it with the proper data
-- to display the proper aura.
local function set_aura(frame, db, aura_controls, aura, i, is_friend)
	local control = aura_controls[i]

	local id, slot, quality, is_buff, name, _, icon, count, debuff_type, duration, expiration_time, caster, _, _, spell_id, _, _, _, _, time_mod = unpack(aura, 1, ENTRY_END)

	local is_mine = my_units[caster]
	local who = is_mine and "my" or "other"
	-- No way to know who applied a weapon buff so we have a separate
	-- category for them.
	if slot then who = "weapon" end
	local rule = who .. '_' .. (is_buff and "buffs" or "debuffs")

	if not control then
		control = PitBull4.Controls.MakeAura(frame)
		control.cooldown.noCooldownCount = db.suppress_occ or nil
		aura_controls[i] = control
	end

	local layout = is_buff and db.layout.buff or db.layout.debuff
	control:SetFrameLevel(frame:GetFrameLevel() + layout.frame_level)

	local unchanged = id == control.id and expiration_time == control.expiration_time and spell_id == control.spell_id and slot == control.slot and is_buff == control.is_buff and caster == control.caster and count == control.count and duration == control.duration and time_mod == control.time_mod

	control.id = id
	control.is_mine = is_mine
	control.is_buff = is_buff
	control.name = name
	control.count = count
	control.duration = duration
	control.expiration_time = expiration_time
	control.debuff_type = debuff_type
	control.slot = slot
	control.caster = caster
	control.spell_id = spell_id
	control.time_mod = time_mod

	local class_db = frame.classification_db
	if not db.click_through and class_db and not class_db.click_through then
		control:EnableMouse(true)
	else
		control:EnableMouse(false)
	end

	local texture = control.texture
	texture:SetTexture(icon)

	if not frame.masque_group then
		if db.zoom_aura then
			texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end

	local texts = db.texts[rule]
	local count_db = texts.count
	local font,font_size = frame:GetFont(count_db.font, count_db.size)
	local count_text = control.count_text
	local count_anchor = count_db.anchor
	local count_color = count_db.color
	count_text:ClearAllPoints()
	count_text:SetPoint(count_anchor,control,count_anchor,count_db.offset_x,count_db.offset_y)
	count_text:SetFont(font, font_size, "OUTLINE")
	count_text:SetTextColor(count_color[1],count_color[2],count_color[3],count_color[4])
	count_text:SetText(count > 1 and count or "")

	if db.cooldown[rule] and duration and duration > 0 then
		local cooldown = control.cooldown
		-- Avoid updating the cooldown frame if nothing changed to stop the flashing Aura
		-- problem since 4.0.1.
		if not unchanged or not cooldown:IsShown() then
			cooldown:Show()
			CooldownFrame_Set(cooldown, expiration_time - duration, duration, 1)
		end
	else
		control.cooldown:SetCooldown(0, 0)
		control.cooldown:Hide()
	end

	if db.cooldown_text[rule] and duration and duration > 0 then
		local cooldown_text = control.cooldown_text
		local cooldown_text_db = texts.cooldown_text
		local color = cooldown_text_db.color
		local r,g,b,a = color[1],color[2],color[3],color[4]
		font,font_size = frame:GetFont(cooldown_text_db.font, cooldown_text_db.size)
		cooldown_text:SetFont(font, font_size, "OUTLINE")
		cooldown_text:ClearAllPoints()
		local anchor = cooldown_text_db.anchor
		cooldown_text:SetPoint(anchor,control,anchor,cooldown_text_db.offset_x,cooldown_text_db.offset_y)
		local color_by_time = cooldown_text_db.color_by_time
		if not color_by_time then
			cooldown_text:SetTextColor(r,g,b,a)
		end
		cooldown_text.color_by_time = cooldown_text_db.color_by_time
		PitBull4_Aura:EnableCooldownText(control)
	else
		PitBull4_Aura:DisableCooldownText(control)
	end

	local border_db
	if who == "weapon" then
		border_db = db.borders[rule]
	else
		border_db = db.borders[rule][is_friend and "friend" or "enemy"]
	end
	if border_db.enabled then
		local border = control.border
		local colors = PitBull4_Aura.db.profile.global.colors
		border:Show()
		local color_type = border_db.color_type

		if color_type == "weapon" and quality then
			local r,g,b = GetItemQualityColor(quality)
			border:SetVertexColor(r,g,b)
		elseif color_type == "type" then
			local color = colors.type[tostring(debuff_type)]
			if not color then
				-- Use the Other color if there's not
				-- a color for the specific debuff type.
				color = colors.type["nil"]
			end
			border:SetVertexColor(unpack(color))
		elseif color_type == "caster" then
			border:SetVertexColor(unpack(colors.caster[who]))
		elseif color_type == "custom" and border_db.custom_color then
			border:SetVertexColor(unpack(border_db.custom_color))
		else
			-- Unknown color type just set it to red, shouldn't actually
			-- ever get to this code
			border:SetVertexColor(1,0,0)
		end
	else
		control.border:Hide()
	end
end

local function update_auras(frame, db, is_buff)
	-- Get the controls table
	local controls
	if is_buff then
		controls = frame.aura_buffs
		if not controls then
			controls = {}
			frame.aura_buffs = controls
		end
	else
		controls = frame.aura_debuffs
		if not controls then
			controls = {}
			frame.aura_debuffs = controls
		end
	end
	local unit = frame.unit
	local is_friend = unit and UnitIsFriend("player", unit)
	local is_player = unit and UnitIsUnit(unit, "player")

	local max = is_buff and db.max_buffs or db.max_debuffs

	get_aura_list(list, unit, db, is_buff, frame)


	-- If weapons are enabled and the unit is the player
	-- copy the weapon entries into the aura list
	if is_buff and db.enabled_weapons and unit and is_player then
		local filter = db.layout.buff.filter
		copy_weapon_entry(weapon_list, list, INVSLOT_MAINHAND)
		if list[#list] and not PitBull4_Aura:FilterEntry(filter, list[#list], frame) then
			list[#list] = del_entry(list[#list])
		end
		copy_weapon_entry(weapon_list, list, INVSLOT_OFFHAND)
		if list[#list] and not PitBull4_Aura:FilterEntry(filter, list[#list], frame) then
			list[#list] = del_entry(list[#list])
		end
	end

	if frame.force_show then
		-- config mode so treat sample frames as friendly
		if not unit or not UnitExists(unit) then
			is_friend = true
		end

		-- Fill extra auras if we're in config mode
		get_aura_list_sample(list, unit, max, db, is_buff, is_player)
	end

	local layout = is_buff and db.layout.buff or db.layout.debuff
	if layout.sort then
		aura_sort__is_friend = is_friend
		aura_sort__is_buff = is_buff
		sort(list, aura_sort)
	end

	-- Limit the number of displayed buffs here after we
	-- have filtered and sorted to allow the most important
	-- auras to be displayed rather than randomly tossing
	-- some away that may not be our prefered auras
	local buff_count = (#list > max) and max or #list

	for i = 1, buff_count do
		set_aura(frame, db, controls, list[i], i, is_friend)
	end

	-- Remove unnecessary aura frames
	for i = buff_count + 1, #controls do
		controls[i] = controls[i]:Delete()
	end
end

-- TODO Configurable formatting
local function format_time(seconds)
	if seconds >= 86400 then
		return DAY_ONELETTER_ABBR,floor(seconds/86400)
	elseif seconds >= 3600 then
		return HOUR_ONELETTER_ABBR,ceil(seconds/3600)
	elseif seconds >= 180 then
		return MINUTE_ONELETTER_ABBR,ceil(seconds/60)
	elseif seconds > 60 then
		seconds = ceil(seconds)
		return "%d:%02d",seconds/60,seconds%60
	elseif seconds < 3 then
		return "%.1f",seconds
	else
		return "%d",ceil(seconds)
	end
end

local function update_cooldown_text(aura)
	local cooldown_text = aura.cooldown_text
	if not cooldown_text:IsShown() then return end
	local expiration_time = aura.expiration_time
	if not expiration_time then return end
	local duration = aura.duration
	local color_by_time = cooldown_text.color_by_time

	local current_time = GetTime()
	local time_left = expiration_time - current_time
	if aura.time_mod > 0 then
		time_left = time_left / aura.time_mod
	end

	local new_time
	if time_left >= 0 then
		if time_left >= 3600 then
			new_time = 30
		elseif time_left >= 180 then
			new_time = 1
		elseif time_left >= 60 then
			new_time = 0.5
		elseif time_left < 3 then
			new_time = 0
		else
			new_time = 0.25
		end
		if color_by_time and duration and duration > 0 then
			local duration_left = time_left / duration
			if duration_left >= 0.3 then
				-- More than 30% so green
				cooldown_text:SetTextColor(0,1,0,1)
			elseif duration_left >= 0.2 then
				-- fade from green to yellow betwee 30% left to 20% left
				local r = 1 - ((duration_left - 0.2) * 10)
				cooldown_text:SetTextColor(r,1,0,1)
			elseif duration_left >= 0.1 then
				-- fade from yellow to red betwee 20% left to 10% left
				local g = (duration_left - 0.1) * 10
				cooldown_text:SetTextColor(1,g,0,1)
			else
				-- less than 10% so stay red.
				cooldown_text:SetTextColor(1,0,0,1)
			end
		end
		cooldown_text:SetFormattedText(format_time(time_left))
	else
		cooldown_text:SetText("")
	end
	return new_time
end

local function clear_auras(frame, is_buff)
	local controls
	if is_buff then
		controls = frame.aura_buffs
	else
		controls = frame.aura_debuffs
	end

	if not controls then
		return
	end

	for i = 1, #controls do
		controls[i].cooldown.noCooldownCount = nil
		controls[i] = controls[i]:Delete()
	end
end

function PitBull4_Aura:ClearAuras(frame)
	clear_auras(frame, true) -- Buffs
	clear_auras(frame, false) -- Debuffs
end

function PitBull4_Aura:UpdateAuras(frame)
	local db = self:GetLayoutDB(frame)
	local highlight = db.highlight

	-- Start the Highlight Filter System
	if highlight then
		self:HighlightFilterStart()
	end

	-- Buffs
	if db.enabled_buffs then
		update_auras(frame, db, true)
	else
		clear_auras(frame, true)
		if highlight then
			-- Iterate the auras for highlighting, normally
			-- this is done as part of the aura update process
			-- but we have to do it separately when it is disabled.
			self:HighlightFilterIterator(frame, db, true)
		end
	end

	-- Debuffs
	if db.enabled_debuffs then
		update_auras(frame, db, false)
	else
		clear_auras(frame, false)
		if highlight then
			-- Iterate the auras for highlighting, normally
			-- this is done as part of the aura update process
			-- but we have to do it separately when it is disabled.
			self:HighlightFilterIterator(frame, db, false)
		end
	end

	-- Finish the Highlight Filter System
	if highlight then
		self:SetHighlight(frame, db)
	end
end

local cooldown_texts = {}

function PitBull4_Aura:EnableCooldownText(aura)
	local cooldown_text = aura.cooldown_text
	if not cooldown_text then return end
	cooldown_text:Show()
	cooldown_texts[aura] = 0
	self.next_text_update = 0
end

function PitBull4_Aura:DisableCooldownText(aura)
	local cooldown_text = aura.cooldown_text
	if cooldown_text then
		cooldown_text:Hide()
	end
	cooldown_texts[aura] = nil
end

function PitBull4_Aura:UpdateCooldownTexts(elapsed)
	local min_time
	for aura,time in pairs(cooldown_texts) do
		time = time - elapsed
		if time <= 0 then
			time = update_cooldown_text(aura,elapsed)
		end
		cooldown_texts[aura] = time
		if not min_time or (time and time < min_time) then
			min_time = time
		end
	end
	return min_time
end

-- Looks for changes to weapon enchants that we do not have cached
-- and if there is one updates all the frames set to display them.
-- If force is set then it clears the cache first.  Useful for
-- config changes that may invalidate our cache.
--
-- General operation of the Weapon Enchant aura system:
-- * Load changed weapon enchants into weapon_list which
--   is an table of aura entries identical in layout to list
-- * The aura entries are indexed by the slot id of the weapon.
-- * When a frames auras are updated (either normally or triggered
--   by a weapon enchant change) the weapon enchants are copied
--   into the list of auras built from UnitAura().
--
-- This design means that the tooltip scanning, duration calculations,
-- and spell icon guessing operations only happen once when the
-- weapon enchant is first seen.  Other arua changes for the player
-- simply cause the weapon enchant data to be copied again without
-- recalculation.
function PitBull4_Aura:UpdateWeaponEnchants(force)
	local updated = false
	if force then
		wipe(weapon_list)
	end
	local mh, mh_time_left, mh_count, _, oh, oh_time_left, oh_count = GetWeaponEnchantInfo()
	local current_time = GetTime()
	local mh_entry = weapon_list[INVSLOT_MAINHAND]
	local oh_entry = weapon_list[INVSLOT_OFFHAND]

	-- Grab the values from the weapon_list entries to use
	-- to compare against the current values to look for changes.
	local old_mh, old_mh_count, old_mh_expiration_time
	if mh_entry then
		old_mh = mh_entry[2] ~= nil and true or false
		old_mh_count = mh_entry[8]
		old_mh_expiration_time = mh_entry[11]
	end

	local old_oh, old_oh_count, old_oh_expiration_time
	if oh_entry then
		old_oh = oh_entry[2] ~= nil and true or false
		old_oh_count = oh_entry[8]
		old_oh_expiration_time = oh_entry[11]
	end

	-- GetWeaponEnchantInfo() briefly returns that there is
	-- an enchant but with the time_left set to zero.
	-- When this happens force it to appear to us as though
	-- the enchant isn't there.
	if mh_time_left == 0 then
		mh, mh_time_left, mh_count = nil, nil, nil
	end
	if oh_time_left == 0 then
		oh, oh_time_left, oh_count = nil, nil, nil
	end

	-- Calculate the expiration time from the time left.  We use
	-- expiration time since the normal Aura system uses it instead
	-- of time_left.
	local mh_expiration_time = mh_time_left and mh_time_left / 1000 + current_time
	local oh_expiration_time = oh_time_left and oh_time_left / 1000 + current_time

	-- Test to see if the enchant has changed and if so set the entry for it
	-- We check that the expiration time is at least 0.2 seconds further
	-- ahead than it was to avoid rebuilding auras for rounding errors.
	if mh ~= old_mh or mh_count ~= old_mh_count or (mh_expiration_time and old_mh_expiration_time and mh_expiration_time - old_mh_expiration_time > 0.2) then
		set_weapon_entry(weapon_list, mh, mh_time_left, mh_expiration_time, mh_count, INVSLOT_MAINHAND)
		updated = true
	end
	if oh ~= old_oh or oh_count ~= old_oh_count or (oh_expiration_time and old_oh_expiration_time and oh_expiration_time - old_oh_expiration_time > 0.2) then
		set_weapon_entry(weapon_list, oh, oh_time_left, oh_expiration_time, oh_count, INVSLOT_OFFHAND)
		updated = true
	end

	-- An enchant changed so find all the relevent frames and update
	-- their auras.
	if updated then
		for frame in PitBull4:IterateFrames() do
			local unit = frame.unit
			if unit and UnitIsUnit(unit, "player") then
				local db = self:GetLayoutDB(frame)
				if db.enabled and db.enabled_weapons then
					self:UpdateAuras(frame)
					self:LayoutAuras(frame)
				end
			end
		end
	end
end

-- table of frames to be updated on next filter update
local timed_filter_update = {}

--- Request that a frame is updated on the next timed update
-- The frame will only be updated once.  This is useful for
-- filters to request they be rerun on a frame for data that
-- changes with time.
-- @param frame the frame to update
-- @usage PitBull4_aura:RequestTimeFilterUpdate(my_frame)
-- @return nil
function PitBull4_Aura:RequestTimedFilterUpdate(frame)
	timed_filter_update[frame] = true
end

function PitBull4_Aura:UpdateFilters()
	for frame in pairs(timed_filter_update) do
		timed_filter_update[frame] = nil
		self:UpdateAuras(frame)
		self:LayoutAuras(frame)
	end
end

local guids_to_update = {}

function PitBull4_Aura:UNIT_AURA(event, unit)
	-- UNIT_AURA updates are throttled by collecting them in
	-- guids_to_update and then updating the relevent frames
	-- once every 0.2 seconds.  We capture the GUID at the event
	-- time because the unit ids can change between when we receive
	-- the event and do the throttled update
	local guid = unit and UnitGUID(unit)
	if guid then
		guids_to_update[guid] = true
	end
end

-- Function to execute the throttled updates
function PitBull4_Aura:OnUpdate()
	if next(guids_to_update) then
		for frame in PitBull4:IterateFrames() do
			if guids_to_update[frame.guid] then
				if self:GetLayoutDB(frame).enabled then
					self:UpdateFrame(frame)
				else
					self:ClearFrame(frame)
				end
			end
		end
		wipe(guids_to_update)
	end

	self:UpdateWeaponEnchants()

	self:UpdateFilters()
end

function PitBull4_Aura:UpdateAll()
	for frame in PitBull4:IterateFrames() do
		self:Update(frame)
	end
	wipe(guids_to_update)
end

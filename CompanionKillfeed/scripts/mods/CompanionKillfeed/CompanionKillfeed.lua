local mod = get_mod("CompanionKillfeed")

local show_in_main_feed   = true
local show_separate_feed  = true
local show_dog            = true
local show_servo_skull    = true
local show_all_companions = true
local name_format         = "companion_name"

local function cache_settings()
	show_in_main_feed   = mod:get("show_in_main_feed")
	show_separate_feed  = mod:get("show_separate_feed")
	show_dog            = mod:get("show_dog")
	show_servo_skull    = mod:get("show_servo_skull")
	show_all_companions = mod:get("show_all_companions")
	name_format         = mod:get("name_format")
end

mod.on_all_mods_loaded = cache_settings
mod.on_setting_changed = cache_settings

local companion_feed_element = nil
local last_companion_killer_type = nil
local last_companion_killer_unit = nil

local function get_local_player()
	if Managers.player then
		return Managers.player:local_player(1)
	end
	return nil
end

mod.on_game_state_changed = function(status, state)
	if state == "GameplayStateRun" then
		if status == "exit" then
			companion_feed_element = nil
		end
	end
end

local DEFAULT_COLOR = { 208, 136, 48 }

local Breed = require("scripts/utilities/breed")

local function get_companion_owner(unit)
	if not Managers.player then return nil end

	local players = Managers.player:players()
	for _, player in pairs(players) do
		local player_unit = player.player_unit
		if player_unit and ALIVE[player_unit] then
			local spawner_ext = ScriptUnit.has_extension(player_unit, "companion_spawner_system")
			if spawner_ext and spawner_ext._spawned_units then
				for _, spawned_unit in ipairs(spawner_ext._spawned_units) do
					if spawned_unit == unit then
						return player
					end
				end
			end
		end
	end

	return nil
end

local function unit_is_companion(unit)
	if get_companion_owner(unit) ~= nil then
		return true
	end
	return false
end

local function get_companion_type(unit)
	local ext = ScriptUnit.has_extension(unit, "unit_data_system")
	if not ext then return "skull" end
	local breed = ext:breed()
	if breed and breed.name and string.find(breed.name, "dog", 1, true) then
		return "dog"
	end
	return "skull"
end

local function get_companion_display_name(unit, ctype)
	local owner = get_companion_owner(unit)
	if not owner then return nil end

	local profile = owner:profile()
	if not profile then return nil end

	local given = nil

	if ctype == "skull" then
		local servo_mod = get_mod("ServoSkullNametag")
		if servo_mod and owner.player_unit then
			local spawner_ext = ScriptUnit.has_extension(owner.player_unit, "companion_spawner_system")
			if spawner_ext then
				local SpecialRules = require("scripts/settings/ability/special_rules_settings").special_rules
				local skulls = {
					base = spawner_ext:spawned_unit_lookup(SpecialRules.cryptic_servo_skull_hack),
					flame = spawner_ext:spawned_unit_lookup(SpecialRules.cryptic_servo_skull_flamethrower),
					med = spawner_ext:spawned_unit_lookup(SpecialRules.cryptic_servo_skull_inject_ally),
				}
				for skull_type, skull_unit in pairs(skulls) do
					if skull_unit == unit then
						local name = servo_mod.get_skull_name(owner, skull_type)
						if name and name ~= "" then
							given = name
						end
						break
					end
				end
			end
		end
	end

	if not given then
		given = profile.companion and profile.companion.name
	end

	local char_name = profile.name or "Unknown"

	if name_format == "player_name" then
		return char_name
	end

	local base_name = (given and given ~= "") and given or (ctype == "dog" and "Dog" or "Servo Skull")
	local companion_type_name = ctype == "dog" and "Dog" or "Servo Skull"

	if name_format == "companion_and_player" then
		return string.format("%s (%s)", base_name, char_name)
	elseif name_format == "player_possessive" then
		if given and given ~= "" then
			return string.format("%s's %s %s", char_name, companion_type_name, given)
		else
			return string.format("%s's %s", char_name, companion_type_name)
		end
	end

	if given and given ~= "" then
		return given
	end

	if ctype == "dog" then
		return char_name .. "'s Dog"
	end
	return char_name .. "'s Servo Skull"
end

local function get_companion_color(unit)
	local owner = get_companion_owner(unit)
	if not owner then return DEFAULT_COLOR end

	local player_slot = owner.slot and owner:slot()
	if player_slot then
		local UISettings = require("scripts/settings/ui/ui_settings")
		if UISettings and UISettings.player_slot_colors then
			local slot_color = UISettings.player_slot_colors[player_slot]
			if slot_color then
				return slot_color
			end
		end
	end

	return DEFAULT_COLOR
end

local function colorize(text, color)
	local Text = require("scripts/utilities/ui/text")
	return Text.apply_color_to_text(text, color)
end

local function get_victim_display_name(unit)
	local ext   = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = ext and ext:breed()
	if breed and breed.display_name then
		return Localize(breed.display_name)
	end
	return "Enemy"
end

local function inject_hud_element(instance)
	if not table.find_by_key(instance, "class_name", "HudElementCompanionCombatFeed") then
		table.insert(instance, {
			class_name = "HudElementCompanionCombatFeed",
			filename = "scripts/ui/hud/elements/combat_feed/hud_element_combat_feed",
			use_hud_scale = true,
			visibility_groups = {
				"dead",
				"alive",
				"communication_wheel",
				"tactical_overlay",
			},
		})
	end
end

mod:hook_require("scripts/ui/hud/hud_elements_player_onboarding", inject_hud_element)
mod:hook_require("scripts/ui/hud/hud_elements_player", inject_hud_element)

mod:hook("HudElementCombatFeed", "_get_unit_presentation_name", function(func, self, unit)
	local is_companion = false
	local ctype = nil
	local companion_unit = unit

	if unit_is_companion(unit) then
		is_companion = true
		ctype = get_companion_type(unit)
	elseif last_companion_killer_type and last_companion_killer_unit then
		local local_player = get_local_player()
		local owner = get_companion_owner(last_companion_killer_unit)
		if owner and owner.player_unit == unit then
			is_companion = true
			ctype = last_companion_killer_type
			companion_unit = last_companion_killer_unit
		end
	end

	if is_companion then
		if ctype == "dog" and not show_dog then
			return func(self, unit)
		end
		if ctype == "skull" and not show_servo_skull then
			return func(self, unit)
		end

		if not show_all_companions then
			local owner = get_companion_owner(companion_unit)
			local local_player = get_local_player()
			if not owner or owner ~= local_player then
				return func(self, unit)
			end
		end

		local name = get_companion_display_name(companion_unit, ctype)
		if name then
			local color = get_companion_color(companion_unit)
			return colorize(name, color)
		end
	end

	return func(self, unit)
end)

local main_feed_element = nil

mod:hook("HudElementCombatFeed", "init", function(func, self, parent, draw_layer, start_scale)
	func(self, parent, draw_layer, start_scale)

	if not main_feed_element then
		main_feed_element = self
	elseif not companion_feed_element and self ~= main_feed_element then
		self._is_companion_feed = true
		companion_feed_element  = self
		
		local widgets = self._widgets
		if widgets then
			for _, widget in pairs(widgets) do
				if widget.offset then
					widget.offset[2] = (widget.offset[2] or 0) - 250
				end
			end
		end
	end
end)

mod:hook("HudElementCombatFeed", "destroy", function(func, self)
	if self == main_feed_element then
		main_feed_element = nil
	end
	if self == companion_feed_element then
		companion_feed_element = nil
	end
	func(self)
end)

mod:hook("HudElementCombatFeed", "event_combat_feed_kill", function(func, self, attacking_unit, attacked_unit)
	if self._is_companion_feed then
		return
	end

	local actual_attacking_unit = attacking_unit
	if last_companion_killer_type and last_companion_killer_unit then
		local owner = get_companion_owner(last_companion_killer_unit)
		if owner and owner.player_unit == attacking_unit then
			actual_attacking_unit = last_companion_killer_unit
		end
	end

	local is_companion = unit_is_companion(actual_attacking_unit)
	local should_show_companion = false

	if is_companion then
		local ctype = get_companion_type(actual_attacking_unit)
		should_show_companion = true

		if ctype == "dog" and not show_dog then
			should_show_companion = false
		elseif ctype == "skull" and not show_servo_skull then
			should_show_companion = false
		end

		if should_show_companion and not show_all_companions then
			local owner = get_companion_owner(actual_attacking_unit)
			local local_player = get_local_player()
			if not owner or owner ~= local_player then
				should_show_companion = false
			end
		end
	end

	if is_companion and should_show_companion and show_in_main_feed and companion_feed_element then
		func(companion_feed_element, actual_attacking_unit, attacked_unit)
	end

	if not is_companion or (should_show_companion and show_separate_feed) then
		func(self, actual_attacking_unit, attacked_unit)
	end
end)

mod:hook("AttackReportManager", "_process_attack_result", function(func, self, buffer_data)
	local profile_name = buffer_data.damage_profile and buffer_data.damage_profile.name
	if profile_name then
		if string.find(profile_name, "companion") or string.find(profile_name, "servo_skull") then
			last_companion_killer_type = "any"
		end
	end

	if last_companion_killer_type and buffer_data.attacking_unit then
		local owner = get_companion_owner(buffer_data.attacking_unit)
		local player = owner or (Managers.player and Managers.player:player_by_unit(buffer_data.attacking_unit))
		if player and player.player_unit then
			local spawner_ext = ScriptUnit.has_extension(player.player_unit, "companion_spawner_system")
			if spawner_ext and spawner_ext._spawned_units then
				for _, spawned_unit in ipairs(spawner_ext._spawned_units) do
					local c_type = get_companion_type(spawned_unit)
					if last_companion_killer_type == "any" or c_type == last_companion_killer_type then
						last_companion_killer_unit = spawned_unit
						last_companion_killer_type = c_type
						break
					end
				end
			end
		end
	end

	func(self, buffer_data)

	last_companion_killer_type = nil
	last_companion_killer_unit = nil
end)


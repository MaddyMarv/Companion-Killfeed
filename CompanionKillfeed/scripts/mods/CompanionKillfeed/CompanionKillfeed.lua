local mod = get_mod("CompanionKillfeed")

local show_in_main_feed   = true
local show_separate_feed  = false
local my_feed_routing     = "main_feed_only"
local allied_feed_routing = "main_feed_only"
local show_dog            = true
local show_servo_flame    = true
local show_servo_hacker   = true
local show_servo_lasgun   = true
local show_servo_medic    = true
local show_non_elite_kills = false
local name_format         = "companion_name"
local offset_x            = 0
local offset_y            = 300

local function cache_settings()
	my_feed_routing     = mod:get("my_feed_routing") or "main_feed_only"
	show_in_main_feed   = (my_feed_routing == "main_feed_only" or my_feed_routing == "both_feeds")
	show_separate_feed  = (my_feed_routing == "separate_feed_only" or my_feed_routing == "both_feeds")
	allied_feed_routing = mod:get("allied_feed_routing") or "main_feed_only"
	show_dog            = mod:get("show_dog")
	show_servo_flame    = mod:get("show_servo_flame")
	show_servo_hacker   = mod:get("show_servo_hacker")
	show_servo_lasgun   = mod:get("show_servo_lasgun")
	show_servo_medic    = mod:get("show_servo_medic")
	show_non_elite_kills = mod:get("show_non_elite_kills")
	stack_non_elite_kills = mod:get("stack_non_elite_kills")
	name_format         = mod:get("name_format")
	offset_x            = mod:get("offset_x") or 0
	offset_y            = mod:get("offset_y") or 300
end

mod.on_all_mods_loaded = cache_settings

mod.on_setting_changed = function(setting_id)
	cache_settings()
	if companion_feed_element and companion_feed_element.set_scenegraph_position and companion_feed_element._ui_scenegraph then
		local has_combat_feed = false
		local has_pivot = false
		local has_background = false
		for k, _ in pairs(companion_feed_element._ui_scenegraph) do
			if k == "combat_feed" then has_combat_feed = true end
			if k == "pivot" then has_pivot = true end
			if k == "background" then has_background = true end
		end
		
		if has_combat_feed then
			companion_feed_element:set_scenegraph_position("combat_feed", offset_x, offset_y, nil)
		elseif has_pivot then
			companion_feed_element:set_scenegraph_position("pivot", offset_x, offset_y, nil)
		elseif has_background then
			companion_feed_element:set_scenegraph_position("background", offset_x, offset_y, nil)
		end
	end
end

local companion_feed_element = nil
local last_companion_killer_type = nil
local last_companion_killer_unit = nil
local lazy_identify

local function get_local_player()
	if Managers.player then
		return Managers.player:local_player(1)
	end
	return nil
end

mod.on_game_state_changed = function(status, state)
	if state == "GameplayStateRun" and status == "exit" then
		companion_feed_element = nil
	end
end

local DEFAULT_COLOR = { 208, 136, 48 }

local Breed = require("scripts/utilities/breed")

local function get_all_companion_units(spawner_ext)
	local units = {}
	if spawner_ext._spawned_units then
		for _, u in ipairs(spawner_ext._spawned_units) do
			table.insert(units, u)
		end
	end
	
	local SpecialRules = require("scripts/settings/ability/special_rules_settings").special_rules
	if SpecialRules and spawner_ext.spawned_unit_lookup then
		local rules = {
			"cryptic_servo_skull",
			"cryptic_servo_skull_lasgun",
			"cryptic_servo_skull_flamethrower",
			"cryptic_servo_skull_hack",
			"cryptic_servo_skull_inject_ally"
		}
		for _, rule_name in ipairs(rules) do
			local success, rule = pcall(function() return SpecialRules[rule_name] end)
			if success and rule then
				local u = spawner_ext:spawned_unit_lookup(rule)
				if u then table.insert(units, u) end
			end
		end
	end
	return units
end

local function get_companion_owner(unit)
	if not Managers.player then return nil end

	local players = Managers.player:players()
	for _, player in pairs(players) do
		local player_unit = player.player_unit
		if player_unit and ALIVE[player_unit] then
			local spawner_ext = ScriptUnit.has_extension(player_unit, "companion_spawner_system")
			if spawner_ext then
				local companions = get_all_companion_units(spawner_ext)
				for _, spawned_unit in ipairs(companions) do
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
	if not unit or not ALIVE[unit] then return "skull" end

	local ext = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = ext and ext.breed and ext:breed()
	if breed and breed.name and string.find(breed.name, "dog", 1, true) then
		return "dog"
	end

	local owner = get_companion_owner(unit)
	if owner and owner.player_unit and ALIVE[owner.player_unit] then
		local spawner_ext = ScriptUnit.has_extension(owner.player_unit, "companion_spawner_system")
		if spawner_ext then
			local SpecialRules = require("scripts/settings/ability/special_rules_settings").special_rules
			if SpecialRules and spawner_ext.spawned_unit_lookup then
				if spawner_ext:spawned_unit_lookup(SpecialRules.cryptic_servo_skull_flamethrower) == unit then return "skull_flame" end
				if spawner_ext:spawned_unit_lookup(SpecialRules.cryptic_servo_skull_hack) == unit then return "skull_hacker" end
				if spawner_ext:spawned_unit_lookup(SpecialRules.cryptic_servo_skull_inject_ally) == unit then return "skull_medic" end
			end
			return "skull_lasgun"
		end
	end

	return "skull"
end

local function get_companion_display_name(unit, ctype)
	local owner = get_companion_owner(unit)
	if not owner then return nil end

	local profile = owner:profile()
	if not profile then return nil end

	local given = nil

	if string.sub(ctype, 1, 5) == "skull" then
		local servo_mod = get_mod("ServoSkullNametag")
		if servo_mod and owner.player_unit and ALIVE[owner.player_unit] then
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

	local icon = ""
	local servo_mod = get_mod("ServoSkullNametag")
	if servo_mod then
		if ctype == "skull_flame" then icon = servo_mod:get("icon_flame") or ""
		elseif ctype == "skull_medic" then icon = servo_mod:get("icon_med") or ""
		elseif ctype == "skull_hacker" or ctype == "skull_lasgun" or ctype == "skull_base" or ctype == "skull" then icon = servo_mod:get("icon_base") or ""
		elseif ctype == "dog" then icon = "" end
	else
		if ctype == "skull_flame" then icon = ""
		elseif ctype == "skull_medic" then icon = ""
		elseif ctype == "skull_hacker" or ctype == "skull_lasgun" or ctype == "skull_base" or ctype == "skull" then icon = ""
		elseif ctype == "dog" then icon = "" end
	end
	if icon and icon ~= "" then icon = icon .. " " end

	local companion_type_name = "Servo Skull"
	if ctype == "dog" then
		companion_type_name = "Cyber-Mastiff"
	elseif ctype == "skull_flame" then
		companion_type_name = "Flame Skull"
	elseif ctype == "skull_medic" then
		companion_type_name = "Medic Skull"
	end

	if name_format == "companion_type_only" then
		return icon .. companion_type_name
	end

	local base_name = given
	if not base_name or base_name == "" then
		base_name = companion_type_name
	end

	if name_format == "companion_and_player" then
		return icon .. string.format("%s (%s)", base_name, char_name)
	elseif name_format == "player_possessive" then
		if given and given ~= "" then
			return icon .. string.format("%s's %s %s", char_name, companion_type_name, given)
		else
			return icon .. string.format("%s's %s", char_name, companion_type_name)
		end
	end

	if given and given ~= "" then
		return icon .. given
	end

	return icon .. char_name .. "'s " .. companion_type_name
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
	if not unit or not ALIVE[unit] then return "Enemy" end
	local ext   = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed = ext and ext.breed and ext:breed()
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

local current_revive_victim = nil

local _skull_prev_states = setmetatable({}, { __mode = "k" })
local STATES = nil
pcall(function() STATES = require("scripts/settings/companion/companion_servo_skull_settings").STATES end)

local _is_our_message = false

local _our_message_route_main = nil
local _our_message_route_separate = nil

local function trigger_manual_feed(skull_unit, ctype, action_text)
	local TextUtilities = require("scripts/utilities/ui/text")
	
	local name = get_companion_display_name(skull_unit, ctype)
	if not name then return end

	local color = get_companion_color(skull_unit)
	local colored_skull = TextUtilities.apply_color_to_text(name, color)

	local msg = string.format("%s %s", colored_skull, action_text)
	
	local route_main = show_in_main_feed
	local route_separate = show_separate_feed

	local owner = get_companion_owner(skull_unit)
	local local_player = get_local_player()
	local is_allied = (owner and owner ~= local_player)

	if is_allied and allied_feed_routing == "off" then
		return
	end

	if is_allied then
		if allied_feed_routing == "off" then return end
		route_main = (allied_feed_routing == "main_feed_only" or allied_feed_routing == "both_feeds")
		route_separate = (allied_feed_routing == "separate_feed_only" or allied_feed_routing == "both_feeds")
	else
		if my_feed_routing == "off" then return end
	end

	_our_message_route_main = route_main
	_our_message_route_separate = route_separate
	_is_our_message = true
	Managers.event:trigger("event_add_combat_feed_message", msg)
	_is_our_message = false
	_our_message_route_main = nil
	_our_message_route_separate = nil
end

mod:hook("HudElementCombatFeed", "event_add_combat_feed_message", function(func, self, message_text, ...)
	lazy_identify(self)
	
	if self._is_companion_feed then
		if not _is_our_message then
			return
		end
		if _our_message_route_separate ~= nil and not _our_message_route_separate then
			return
		end
	else
		if _is_our_message and _our_message_route_main ~= nil and not _our_message_route_main then
			return
		end
	end
	
	func(self, message_text, ...)
end)

mod.update = function(dt)
	if not STATES or not Managers.player or not Managers.state or not Managers.state.game_session then return end
	
	local time_manager = Managers.time
	if not time_manager or not time_manager:has_timer("gameplay") or not time_manager:time("gameplay") then return end

	local game_mode = Managers.state.game_mode
	if not game_mode or game_mode:game_mode_name() == "hub" then return end

	local usp = Managers.state.unit_spawner
	if not usp then return end

	local check_all = (allied_feed_routing ~= "off")
	local local_player = get_local_player()
	
	local players = Managers.player:players()
	for _, player in pairs(players) do
		if check_all or player == local_player then
			local pu = player.player_unit
			if pu and ALIVE[pu] then
				local spawner = ScriptUnit.has_extension(pu, "companion_spawner_system")
				if spawner then
					local skulls = get_all_companion_units(spawner)
					if skulls then
						for i = 1, #skulls do
							local skull = skulls[i]
							if skull and ALIVE[skull] then
								local st = nil
								local gsm = Managers.state and Managers.state.game_session
								local usp = Managers.state and Managers.state.unit_spawner
								if gsm and usp then
									local gs = gsm:game_session()
									local go_id = usp:game_object_id(skull)
									if gs and go_id then
										local ok_e, exists = pcall(GameSession.game_object_exists, gs, go_id)
										if ok_e and exists then
											local ok_b, Breed = pcall(require, "scripts/utilities/breed")
											local breed = (ok_b and Breed) and Breed.unit_breed_or_nil(skull)
											local got = breed and breed.game_object_type
											if got then
												local ok_h, has_state = pcall(function() return Network.object_has_field(got, "state") end)
												if ok_h and has_state then
													local ok_f, state_id = pcall(GameSession.game_object_field, gs, go_id, "state")
													if ok_f then st = state_id end
												end
											end
										end
									end
								end

								if st then
									local prev = _skull_prev_states[skull]
									if prev ~= st then
										_skull_prev_states[skull] = st
										if prev ~= nil then
											local ok_st, skull_settings = pcall(require, "scripts/settings/companion/companion_servo_skull_settings")
											if ok_st and skull_settings and skull_settings.STATES then
												local STATES = skull_settings.STATES
												if st == STATES.inject_ally and mod:get("show_servo_medic") then
													trigger_manual_feed(skull, "skull_medic", "revived an ally")
												elseif st == STATES.hacking and mod:get("show_servo_hacker") then
													trigger_manual_feed(skull, "skull_hacker", "is hacking")
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

mod:hook("HudElementCombatFeed", "_get_unit_presentation_name", function(func, self, unit, is_killer, breed_or_nil, slot_or_nil, ...)
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
		if ctype == "dog" and not show_dog then return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...) end
		if ctype == "skull_flame" and not show_servo_flame then return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...) end
		if ctype == "skull_hacker" and not show_servo_hacker then return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...) end
		if ctype == "skull_lasgun" and not show_servo_lasgun then return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...) end
		if ctype == "skull_medic" and not show_servo_medic then return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...) end
		if ctype == "skull" and not show_servo_lasgun then return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...) end

		local owner = get_companion_owner(companion_unit)
		local local_player = get_local_player()
		local is_allied = (owner and owner ~= local_player)

		if is_allied and allied_feed_routing == "off" then
			return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...)
		elseif not is_allied and my_feed_routing == "off" then
			return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...)
		end

		local name = get_companion_display_name(companion_unit, ctype)
		if name then
			local color = get_companion_color(companion_unit)
			return colorize(name, color)
		end
	end

	return func(self, unit, is_killer, breed_or_nil, slot_or_nil, ...)
end)

local main_feed_element = nil

lazy_identify = function(self)
	if self._companion_feed_checked then return end
	
	if self._parent and self._parent._elements then
		for name, el in pairs(self._parent._elements) do
			if el == self then
				self._companion_feed_checked = true
				if name == "HudElementCompanionCombatFeed" then
					self._is_companion_feed = true
					companion_feed_element = self

					if self.set_scenegraph_position and self._ui_scenegraph then
						local has_combat_feed = false
						local has_pivot = false
						local has_background = false
						for k, _ in pairs(self._ui_scenegraph) do
							if k == "combat_feed" then has_combat_feed = true end
							if k == "pivot" then has_pivot = true end
							if k == "background" then has_background = true end
						end

						if has_combat_feed then
							self:set_scenegraph_position("combat_feed", offset_x, offset_y, nil)
						elseif has_pivot then
							self:set_scenegraph_position("pivot", offset_x, offset_y, nil)
						elseif has_background then
							self:set_scenegraph_position("background", offset_x, offset_y, nil)
						end
					end
				elseif name == "HudElementCombatFeed" then
					main_feed_element = self
				end
				break
			end
		end
	end
end

mod:hook("HudElementCombatFeed", "_enabled", function(func, self, ...)
	lazy_identify(self)
	if self._is_companion_feed and not show_separate_feed then
		return false
	end
	return func(self, ...)
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

local _processed_kills = setmetatable({}, { __mode = "k" })

local temp_kill_message_params = { killer = "n/a", victim = "n/a" }

local function _maybe_merge_companion_kill(self, attacking_unit, attacked_unit)
	if not self._notifications or not self._remove_notification or not self._set_text then
		return
	end

	local unit_data_ext = ScriptUnit.has_extension(attacked_unit, "unit_data_system")
	local breed_or_nil = unit_data_ext and unit_data_ext:breed()
	if not breed_or_nil then
		return
	end

	local tags = breed_or_nil.tags
	if tags and (tags.monster or tags.special or tags.elite or tags.captain or tags.boss) then
		return
	end

	local notifications = self._notifications
	local new_notification = notifications[1]
	if not new_notification then
		return
	end

	new_notification.count = 1
	new_notification.breed = breed_or_nil
	new_notification.player = attacking_unit

	for _, notification in ipairs(notifications) do
		if notification.breed == breed_or_nil
			and notification.player == attacking_unit
			and notification.id ~= new_notification.id then
			new_notification.count = (notification.count or 1) + 1
			self:_remove_notification(notification.id)
		end
	end

	if new_notification.count > 1 then
		local killer = self:_get_unit_presentation_name(attacking_unit, true, nil, 1)
		local victim = self:_get_unit_presentation_name(attacked_unit, false, breed_or_nil, 1)
		temp_kill_message_params.killer = killer
		temp_kill_message_params.victim = victim
		local text = self:_localize("loc_hud_combat_feed_kill_message", true, temp_kill_message_params)
		text = text .. " x" .. tostring(new_notification.count)
		self:_set_text(new_notification.id, text)
	end
end

mod:hook("HudElementCombatFeed", "event_combat_feed_kill", function(func, self, attacking_unit, attacked_unit, weapon_item_or_damage_profile, ...)
	lazy_identify(self)
	if self._is_companion_feed then
		return
	end

	local now = Managers.time and Managers.time:time("gameplay") or 0
	if attacked_unit and _processed_kills[attacked_unit] and (now - _processed_kills[attacked_unit] < 0.1) then
		return
	end
	if attacked_unit and now > 0 then
		_processed_kills[attacked_unit] = now
	end

	local actual_attacking_unit = attacking_unit
	if last_companion_killer_type and last_companion_killer_unit then
		actual_attacking_unit = last_companion_killer_unit
	end

	local is_companion = unit_is_companion(actual_attacking_unit)
	local should_show_companion = false

	if is_companion then
		local ctype = get_companion_type(actual_attacking_unit)
		should_show_companion = true

		if ctype == "dog" and not show_dog then
			should_show_companion = false
		elseif ctype == "skull_flame" and not show_servo_flame then
			should_show_companion = false
		elseif ctype == "skull_hacker" and not show_servo_hacker then
			should_show_companion = false
		elseif ctype == "skull_lasgun" and not show_servo_lasgun then
			should_show_companion = false
		elseif ctype == "skull_medic" and not show_servo_medic then
			should_show_companion = false
		end

		if should_show_companion and allied_feed_routing == "off" then
			local owner = get_companion_owner(actual_attacking_unit)
			local local_player = get_local_player()
			if not owner or owner ~= local_player then
				should_show_companion = false
			end
		end
		local local_player = get_local_player()
		local is_allied = (owner and owner ~= local_player)

		if is_allied and allied_feed_routing == "off" then
			should_show_companion = false
		elseif not is_allied and my_feed_routing == "off" then
			should_show_companion = false
		end
	end

	if is_companion and should_show_companion then
		local route_main = show_in_main_feed
		local route_separate = show_separate_feed

		local owner = get_companion_owner(actual_attacking_unit)
		local local_player = get_local_player()
		local is_allied = (owner and owner ~= local_player)

		if is_allied then
			route_main = (allied_feed_routing == "main_feed_only" or allied_feed_routing == "both_feeds")
			route_separate = (allied_feed_routing == "separate_feed_only" or allied_feed_routing == "both_feeds")
		end

		if route_separate and companion_feed_element then
			func(companion_feed_element, actual_attacking_unit, attacked_unit, weapon_item_or_damage_profile, ...)
			if stack_non_elite_kills then
				_maybe_merge_companion_kill(companion_feed_element, actual_attacking_unit, attacked_unit)
			end
		end
		if route_main then
			func(self, actual_attacking_unit, attacked_unit, weapon_item_or_damage_profile, ...)
			if stack_non_elite_kills then
				_maybe_merge_companion_kill(self, actual_attacking_unit, attacked_unit)
			end
		end
	else
		local pass_unit = actual_attacking_unit
		if is_companion and not should_show_companion then
			local owner = get_companion_owner(actual_attacking_unit)
			if owner and owner.player_unit and ALIVE[owner.player_unit] then
				pass_unit = owner.player_unit
			end
		end
		func(self, pass_unit, attacked_unit, weapon_item_or_damage_profile, ...)
	end
end)

local COMPANION_DAMAGE_PROFILES = {
	["adamant_companion_pounce"] = "dog",
	["adamant_companion_monster_pounce"] = "dog",
	["adamant_companion_human_pounce"] = "dog",
	["adamant_companion_ogryn_pounce"] = "dog",
	["adamant_companion_initial_pounce"] = "dog",
	["adamant_companion_no_damage_pounce"] = "dog",
	["whistle_explosion"] = "dog",
	["close_whistle_explosion"] = "dog",
	
	["companion_servo_skull_flamer"] = "skull_flame",
	["default_companion_servo_skull_lasgun_killshot"] = "skull_lasgun",
	["improved_companion_servo_skull_lasgun_killshot"] = "skull_lasgun",
}

local _dog_targets = setmetatable({}, { __mode = "k" })
local _flame_skull_targets = setmetatable({}, { __mode = "k" })
local _companion_targets = setmetatable({}, { __mode = "k" })

mod:hook("AttackReportManager", "_process_attack_result", function(func, self, buffer_data)
	local profile_name = buffer_data.damage_profile and buffer_data.damage_profile.name
	local is_flame_skull_dot = false
	local is_dog_dot = false
	local now = Managers.time and Managers.time:time("gameplay") or 0

	if buffer_data.attacking_unit and unit_is_companion(buffer_data.attacking_unit) then
		last_companion_killer_unit = buffer_data.attacking_unit
		last_companion_killer_type = get_companion_type(buffer_data.attacking_unit)
		if buffer_data.attacked_unit and now > 0 then
			_companion_targets[buffer_data.attacked_unit] = {
				unit = buffer_data.attacking_unit,
				ctype = last_companion_killer_type,
				time = now,
			}
		end
	end

	if profile_name then
		local companion_type = COMPANION_DAMAGE_PROFILES[profile_name]
		
		if companion_type then
			last_companion_killer_type = companion_type
			
			if companion_type == "dog" and buffer_data.attacked_unit then
				_dog_targets[buffer_data.attacked_unit] = now
			elseif companion_type == "skull_flame" and buffer_data.attacked_unit then
				_flame_skull_targets[buffer_data.attacked_unit] = now
			end
		elseif string.find(profile_name, "companion") or string.find(profile_name, "servo") or string.find(profile_name, "skull") then
			last_companion_killer_type = "skull"
		elseif string.find(profile_name, "burn") or string.find(profile_name, "flam") or string.find(profile_name, "fire") or string.find(profile_name, "soulblaze") or string.find(profile_name, "warpfire") then
			if not string.find(profile_name, "grenade") and not string.find(profile_name, "liquid") then
				local attacked_unit = buffer_data.attacked_unit
				if attacked_unit and _flame_skull_targets[attacked_unit] then
					if now - _flame_skull_targets[attacked_unit] < 10 then
						is_flame_skull_dot = true
					end
				end
			end
		elseif string.find(profile_name, "bleed") then
			is_dog_dot = true
		elseif string.find(profile_name, "electro") or string.find(profile_name, "shock") or string.find(profile_name, "lightning") then
			local attacked_unit = buffer_data.attacked_unit
			if attacked_unit and _dog_targets[attacked_unit] then
				if now - _dog_targets[attacked_unit] < 10 then
					is_dog_dot = true
				end
			end
		end
	end

	if (last_companion_killer_type or is_flame_skull_dot or is_dog_dot) and buffer_data.attacking_unit then
		local owner = get_companion_owner(buffer_data.attacking_unit)
		local player = owner or (Managers.player and Managers.player:player_by_unit(buffer_data.attacking_unit))
		if player and player.player_unit and ALIVE[player.player_unit] then
			local spawner_ext = ScriptUnit.has_extension(player.player_unit, "companion_spawner_system")
			if spawner_ext then
				local companions = get_all_companion_units(spawner_ext)
				if is_flame_skull_dot then
					for _, spawned_unit in ipairs(companions) do
						if get_companion_type(spawned_unit) == "skull_flame" then
							last_companion_killer_unit = spawned_unit
							last_companion_killer_type = "skull_flame"
							break
						end
					end
				elseif is_dog_dot then
					for _, spawned_unit in ipairs(companions) do
						if get_companion_type(spawned_unit) == "dog" then
							last_companion_killer_unit = spawned_unit
							last_companion_killer_type = "dog"
							break
						end
					end
				elseif last_companion_killer_type then
					local fallback_skull_unit = nil
					local fallback_skull_type = nil
					for _, spawned_unit in ipairs(companions) do
						local c_type = get_companion_type(spawned_unit) or ""
						if last_companion_killer_type == "any" or c_type == last_companion_killer_type or (last_companion_killer_type == "skull" and string.find(c_type, "skull")) then
							last_companion_killer_unit = spawned_unit
							last_companion_killer_type = c_type
							fallback_skull_unit = nil
							break
						elseif string.find(last_companion_killer_type, "skull") and string.find(c_type, "skull") then
							if not fallback_skull_unit then
								fallback_skull_unit = spawned_unit
								fallback_skull_type = c_type
							end
						end
					end
					if fallback_skull_unit then
						last_companion_killer_unit = fallback_skull_unit
						last_companion_killer_type = fallback_skull_type
					end
				end
			end
		end
	end

	if last_companion_killer_unit and buffer_data.attacked_unit and now > 0 then
		_companion_targets[buffer_data.attacked_unit] = {
			unit = last_companion_killer_unit,
			ctype = last_companion_killer_type,
			time = now,
		}
	end

	local is_dot = false
	if profile_name then
		if string.find(profile_name, "burn") or string.find(profile_name, "flam") or string.find(profile_name, "fire") or string.find(profile_name, "bleed") or string.find(profile_name, "electro") or string.find(profile_name, "shock") or string.find(profile_name, "lightning") then
			if not string.find(profile_name, "grenade") and not string.find(profile_name, "liquid") then
				is_dot = true
			end
		end
	end

	if buffer_data.attack_result == "died" and buffer_data.attacked_unit then
		local c_unit = nil
		if buffer_data.attacking_unit and unit_is_companion(buffer_data.attacking_unit) then
			c_unit = buffer_data.attacking_unit
		elseif last_companion_killer_unit then
			c_unit = last_companion_killer_unit
		elseif is_dot and _companion_targets[buffer_data.attacked_unit] then
			local entry = _companion_targets[buffer_data.attacked_unit]
			if now - entry.time < 10 and entry.unit and ALIVE[entry.unit] then
				local dot_attacker_owner = buffer_data.attacking_unit and (get_companion_owner(buffer_data.attacking_unit) or (Managers.player and Managers.player:player_by_unit(buffer_data.attacking_unit)))
				local companion_owner = get_companion_owner(entry.unit)
				if dot_attacker_owner and companion_owner and dot_attacker_owner == companion_owner then
					c_unit = entry.unit
				end
			end
		end

		if c_unit and ALIVE[c_unit] then
			local should_display = show_non_elite_kills
			if not should_display then
				local unit_data_ext = ScriptUnit.has_extension(buffer_data.attacked_unit, "unit_data_system")
				local breed = unit_data_ext and unit_data_ext:breed()
				local tags = breed and breed.tags
				if tags and (tags.monster or tags.special or tags.elite) then
					should_display = true
				end
			end

			if should_display then
				Managers.event:trigger("event_combat_feed_kill", c_unit, buffer_data.attacked_unit)
			end
		end
	end

	func(self, buffer_data)

	last_companion_killer_type = nil
	last_companion_killer_unit = nil
end)


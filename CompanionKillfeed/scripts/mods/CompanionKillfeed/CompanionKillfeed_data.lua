local mod = get_mod("CompanionKillfeed")

return {
	name        = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id  = "feed_display",
				type        = "group",
				tab         = mod:localize("tab_general"),
				sub_widgets = {
					{
						setting_id    = "show_in_main_feed",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "show_separate_feed",
						type          = "checkbox",
						default_value = false,
					},
				},
			},
			{
				setting_id  = "visibility",
				type        = "group",
				tab         = mod:localize("tab_general"),
				sub_widgets = {
					{
						setting_id    = "show_all_companions",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "show_non_elite_kills",
						type          = "checkbox",
						default_value = false,
					},
					{
						setting_id    = "stack_non_elite_kills",
						type          = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id  = "positioning",
				type        = "group",
				tab         = mod:localize("tab_general"),
				sub_widgets = {
					{
						setting_id    = "offset_x",
						type          = "numeric",
						default_value = 0,
						range         = {-2000, 2000},
					},
					{
						setting_id    = "offset_y",
						type          = "numeric",
						default_value = 300,
						range         = {-2000, 2000},
					},
				},
			},
			{
				setting_id  = "companion_types",
				type        = "group",
				tab         = mod:localize("tab_companions"),
				sub_widgets = {
					{
						setting_id    = "show_dog",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "show_servo_flame",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "show_servo_hacker",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "show_servo_lasgun",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "show_servo_medic",
						type          = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id  = "formatting",
				type        = "group",
				tab         = mod:localize("tab_companions"),
				sub_widgets = {
					{
						setting_id  = "name_format",
						type        = "dropdown",
						options     = {
							{ value = "companion_name",       text = "companion_name"       },
							{ value = "player_possessive",    text = "player_possessive"    },
							{ value = "companion_and_player", text = "companion_and_player" },
							{ value = "player_name",          text = "player_name"          },
						},
						default_value = "companion_name",
					}
				}
			},
		},
	},
}

return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`CompanionKillfeed` encountered an error loading the Darktide Mod Framework.")

		new_mod("CompanionKillfeed", {
			mod_script       = "CompanionKillfeed/scripts/mods/CompanionKillfeed/CompanionKillfeed",
			mod_data         = "CompanionKillfeed/scripts/mods/CompanionKillfeed/CompanionKillfeed_data",
			mod_localization = "CompanionKillfeed/scripts/mods/CompanionKillfeed/CompanionKillfeed_localization",
		})
	end,
	packages = {},
}

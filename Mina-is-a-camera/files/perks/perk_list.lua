table.insert(perk_list, {
	id = "astral_projection",
	ui_name = "$perk_astral_projection",
	ui_description = "$perkdesc_astral_projection",
	ui_icon = "mods/Mina-is-a-camera/files/perks/astral_projection_icon.png",
	perk_icon = "mods/Mina-is-a-camera/files/perks/astral_projection_icon.png",
	usable_by_enemies = false,
	not_in_default_perk_pool = false,
	stackable = 0,
	func = function(entity_perk_item, entity_who_picked, item_name)
		GameAddFlagRun("astral_projection_perk")
	end,
	func_remove = nil,
	deprecated = nil,
	author = "intrepid",
	local_content = true,
	default = true,
})

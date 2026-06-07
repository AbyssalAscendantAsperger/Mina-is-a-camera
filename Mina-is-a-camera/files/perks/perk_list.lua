table.insert(perk_list, {
    id = "ASTRAL_PROJECTION",
    ui_name = "$perk_ASTRAL_PROJECTION",
    ui_description = "$perkdesc_ASTRAL_PROJECTION",
    ui_icon = "mods/Mina-is-a-camera/files/perks/astral_projection_icon.png",
    perk_icon = "mods/Mina-is-a-camera/files/perks/astral_projection_icon.png",
    usable_by_enemies = false,
    not_in_default_perk_pool = false,
    stackable = 0,
    func = function(entity_perk_item, entity_who_picked, item_name)
        GameAddFlagRun("astral_projection_perk")
    end,
})
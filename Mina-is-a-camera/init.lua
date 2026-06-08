local translations = ModTextFileGetContent("data/translations/common.csv")
translations = translations .. [[
perk_astral_projection,ASTRAL PROJECTION,,,,,,,,,,,,,
perkdesc_astral_projection,Hold ALT to phase through matter,,,,,,,,,,,,,
]]
translations = translations:gsub("\r", "")
ModTextFileSetContent("data/translations/common.csv", translations)

dofile("data/scripts/perks/perk_list.lua")
ModLuaFileAppend("data/scripts/perks/perk_list.lua", "mods/Mina-is-a-camera/files/perks/perk_list.lua")

local player_entity = nil

local saved_x, saved_y, saved_rot, saved_sx, saved_sy = nil, nil, nil, nil, nil

local key_was_down = false
local is_holding = false

local cooldown = 0
local COOLDOWN_MAX = 15

local KEY_LEFT_ALT = 226

local ghost_char_data = nil
local ghost_old_dont_update = nil

local ghost_phys_entries = {}

local last_set_x, last_set_y = nil, nil

local KEY_A = 4
local KEY_D = 7
local KEY_W = 26
local KEY_S = 22
local GHOST_SPEED = 1.0

-- local debug_mod = nil
-- local function try_load_debug(path)
-- local ok, m = pcall(dofile, path)
-- if ok and type(m) == "table" then return m end
-- return nil
-- end
-- debug_mod = try_load_debug("mods/Mina-is-a-camera/debug.lua")
-- if not debug_mod then
-- debug_mod = try_load_debug("mods/Mina-is-a-camera/debug.lua")
-- end
-- if not debug_mod then
-- debug_mod = { print_biome = function() end }
-- end

local function is_player_taking_damage(ent)
	if not ent or not EntityGetIsAlive(ent) then
		return false
	end

	local dmg_comp = EntityGetFirstComponentIncludingDisabled(ent, "DamageModelComponent")
	if not dmg_comp then
		return false
	end

	local ok, last_damage_frame = pcall(ComponentGetValue2, dmg_comp, "mLastDamageFrame")
	if not ok or not last_damage_frame then
		return false
	end

	local current_frame = GameGetFrameNum()
	return (current_frame - last_damage_frame) < 125
end

local function reset_ghost_state()
	if player_entity and EntityGetIsAlive(player_entity) then
		for _, entry in ipairs(ghost_phys_entries) do
			if entry.comp and entry.old ~= nil then
				pcall(ComponentSetValue2, entry.comp, "gridworld_box2d", entry.old)
			end
		end
		ghost_phys_entries = {}

		if ghost_char_data and ghost_old_dont_update ~= nil then
			pcall(ComponentSetValue2, ghost_char_data, "dont_update_velocity_and_xform", ghost_old_dont_update)
			ghost_char_data = nil
			ghost_old_dont_update = nil
		end

		if saved_x ~= nil and saved_y ~= nil then
			EntitySetTransform(player_entity, saved_x, saved_y, saved_rot, saved_sx, saved_sy)
			GamePrintImportant("TELEPORT!", "")
		end
	end

	is_holding = false
	saved_x, saved_y, saved_rot, saved_sx, saved_sy = nil, nil, nil, nil, nil
	last_set_x, last_set_y = nil, nil
end

local function get_player_entity()
	local players = EntityGetWithTag("player")
	if players and #players > 0 then return players[1] end
	players = EntityGetWithTag("player_unit")
	if players and #players > 0 then return players[1] end
	players = EntityGetWithTag("polymorphed_player")
	if players and #players > 0 then return players[1] end
	players = EntityGetWithTag("polymorphed_cessation")
	if players and #players > 0 then return players[1] end
	return nil
end

local BLOCKED_BIOMES = {
	{ pattern = "temple", reason = "Holy Mountain" },
	{ pattern = "vault", reason = "The Vault" },
	{ pattern = "secret", reason = "Secret Room" },
	{ pattern = "boss", reason = "Boss Area" },
	{ pattern = "robobase", reason = "Robot Factory" },
	{ pattern = "wizard", reason = "Wizard Den" },
}

local function is_in_blocked_biome()
	if not player_entity or not EntityGetIsAlive(player_entity) then
		return false, nil
	end
	local x, y = EntityGetTransform(player_entity)
	if not x then return false, nil end

	local ok, biome_file = pcall(DebugBiomeMapGetFilename, x, y)

	-- debug_mod.print_biome(biome_file, not ok or not biome_file)

	if not ok or not biome_file then return false, nil end

	local lower = string.lower(biome_file)
	for _, entry in ipairs(BLOCKED_BIOMES) do
		if string.find(lower, entry.pattern) ~= nil then
			return true, entry.reason
		end
	end
	return false, nil
end

local ITEM_TAGS = { "item_pickup", "heart", "potion", "wand", "orb", "perk", "chest", "gold", "tablet" }

local function is_near_pickup(x, y)
	for _, tag in ipairs(ITEM_TAGS) do
		local ents = EntityGetInRadiusWithTag(x, y, 30, tag)
		if ents then
			for _, ent in ipairs(ents) do
				if ent ~= player_entity then
					local ex, ey = EntityGetTransform(ent)
					if ex and ey then
						local dx, dy = ex - x, ey - y
						local dist = math.sqrt(dx * dx + dy * dy)
						if dist >= 15 and dist <= 30 then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function is_near_liquid(x, y, inner_r, outer_r)
	local angles = {0, 45, 90, 135, 180, 225, 270, 315}
	for _, deg in ipairs(angles) do
		local rad = math.rad(deg)
		local tx = x + math.cos(rad) * outer_r
		local ty = y + math.sin(rad) * outer_r

		local did_hit_liq, hlx, hly = RaytraceSurfacesAndLiquiform(tx, ty, x, y)
		if did_hit_liq then
			local dist_from_player = math.sqrt((hlx - x)^2 + (hly - y)^2)
			if dist_from_player >= inner_r and dist_from_player <= outer_r then
				local did_hit_surf, hsx, hsy = RaytraceSurfaces(tx, ty, x, y)
				if not did_hit_surf then
					return true
				end
				local dist_surf = math.sqrt((hsx - x)^2 + (hsy - y)^2)
				if dist_from_player < dist_surf - 1.0 then
					return true
				end
			end
		end
	end
	return false
end

local function is_deeply_stuck(x, y)
	local dirs = { {4,0}, {-4,0}, {0,4}, {0,-4} }
	local near_count = 0
	for _, d in ipairs(dirs) do
		local hit, hx, hy = RaytraceSurfaces(x + d[1], y + d[2], x, y)
		if hit then
			local dist = math.sqrt((hx - x)^2 + (hy - y)^2)
			if dist < 2.0 then
				near_count = near_count + 1
			end
		end
	end
	return near_count >= 3
end

local function get_stuck_in_ground_counter(ent)
	local comp = EntityGetFirstComponentIncludingDisabled(ent, "PlayerCollisionComponent")
	if not comp then return 0 end
	local ok, val = pcall(ComponentGetValue2, comp, "stuck_in_ground_counter")
	if ok and val then return val end
	return 0
end

local function push_out_of_solid(x, y)
	local candidates = {
		{1.5, 0}, {-1.5, 0}, {0, 1.5}, {0, -1.5},
		{1.1, 1.1}, {-1.1, 1.1}, {1.1, -1.1}, {-1.1, -1.1}
	}
	for _, c in ipairs(candidates) do
		local tx = x + c[1]
		local ty = y + c[2]
		if not is_deeply_stuck(tx, ty) then
			return tx, ty
		end
	end
	return x, y
end

function OnWorldPostUpdate()
	local current_player = get_player_entity()

	if current_player and player_entity and current_player ~= player_entity then
		if player_entity and EntityGetIsAlive(player_entity) then
			for _, entry in ipairs(ghost_phys_entries) do
				if entry.comp and entry.old ~= nil then
					pcall(ComponentSetValue2, entry.comp, "gridworld_box2d", entry.old)
				end
			end
			if ghost_char_data and ghost_old_dont_update ~= nil then
				pcall(ComponentSetValue2, ghost_char_data, "dont_update_velocity_and_xform", ghost_old_dont_update)
			end
		end

		if is_holding and saved_x ~= nil and saved_y ~= nil then
			EntitySetTransform(current_player, saved_x, saved_y, 0, 1, 1)
			GamePrintImportant("TELEPORT!", "")
		end

		is_holding = false
		player_entity = current_player
		ghost_char_data = nil
		ghost_old_dont_update = nil
		ghost_phys_entries = {}
		key_was_down = false
		last_set_x, last_set_y = nil, nil
	end

	if player_entity == nil or not EntityGetIsAlive(player_entity) then
		if is_holding then
			reset_ghost_state()
		end
		if current_player then
			player_entity = current_player
			key_was_down = false
		else
			return
		end
	end

	if not GameHasFlagRun("astral_projection_perk") then
		return
	end

	local px, py = EntityGetTransform(player_entity)

	local in_blocked, block_reason = is_in_blocked_biome()
	if in_blocked then
		if is_holding then
			GamePrintImportant("BLOCKED!", block_reason)
			reset_ghost_state()
			cooldown = COOLDOWN_MAX
			return
		end
	end

	if is_holding and px and is_near_pickup(px, py) then
		GamePrintImportant("BLOCKED!", "Item proximity")
		reset_ghost_state()
		cooldown = COOLDOWN_MAX
		return
	end

	if is_holding and px and is_near_liquid(px, py, 5, 15) then
		GamePrintImportant("BLOCKED!", "Liquid nearby")
		reset_ghost_state()
		cooldown = COOLDOWN_MAX
		return
	end

	if is_holding and is_player_taking_damage(player_entity) then
		GamePrintImportant("BLOCKED!", "Taking damage")
		reset_ghost_state()
		cooldown = COOLDOWN_MAX
		return
	end

	if type(InputIsKeyDown) ~= "function" then
		return
	end

	local is_key_down = InputIsKeyDown(KEY_LEFT_ALT)
	local just_pressed = is_key_down and not key_was_down
	local just_released = (not is_key_down) and key_was_down
	key_was_down = is_key_down

	if cooldown > 0 then
		cooldown = cooldown - 1
		return
	end

	if just_pressed and in_blocked then
		GamePrintImportant("BLOCKED!", block_reason)
		cooldown = COOLDOWN_MAX
		return
	end

	if just_pressed and px and is_near_pickup(px, py) then
		GamePrintImportant("BLOCKED!", "Too close to item")
		cooldown = COOLDOWN_MAX
		return
	end

	if just_pressed and px and is_near_liquid(px, py, 5, 15) then
		GamePrintImportant("BLOCKED!", "Liquid nearby")
		cooldown = COOLDOWN_MAX
		return
	end

	if just_pressed and is_player_taking_damage(player_entity) then
		GamePrintImportant("BLOCKED!", "Taking damage")
		cooldown = COOLDOWN_MAX
		return
	end

	if just_pressed then
		if not is_holding then
			local x, y, rot, sx, sy = EntityGetTransform(player_entity)
			if x ~= nil then
				saved_x = x
				saved_y = y
				saved_rot = rot
				saved_sx = sx
				saved_sy = sy
				is_holding = true
				last_set_x, last_set_y = x, y
				GamePrintImportant("SAVED", "")

				local char_data = EntityGetFirstComponentIncludingDisabled(player_entity, "CharacterDataComponent")
				if char_data then
					local ok_val, val = pcall(ComponentGetValue2, char_data, "dont_update_velocity_and_xform")
					if ok_val then
						ghost_old_dont_update = val
						ghost_char_data = char_data
						pcall(ComponentSetValue2, char_data, "dont_update_velocity_and_xform", true)
					end
				end

				local phys_types = { "PhysicsBodyComponent", "PhysicsBody2Component" }
				for _, ptype in ipairs(phys_types) do
					local comps = EntityGetComponentIncludingDisabled(player_entity, ptype)
					if comps then
						for _, comp in ipairs(comps) do
							local ok_val, val = pcall(ComponentGetValue2, comp, "gridworld_box2d")
							if ok_val then
								table.insert(ghost_phys_entries, { comp = comp, old = val })
								pcall(ComponentSetValue2, comp, "gridworld_box2d", false)
							end
						end
					end
				end
			end
		end
	end

	if just_released then
		if is_holding then
			reset_ghost_state()
		end
	end

	if is_holding then
		local cx, cy, rot, sx, sy = EntityGetTransform(player_entity)

		local stuck_counter = get_stuck_in_ground_counter(player_entity)
		if stuck_counter > 135 then
			GamePrintImportant("BLOCKED!", "Stuck in ground")
			reset_ghost_state()
			cooldown = COOLDOWN_MAX
			return
		end

		local move_speed = GHOST_SPEED
		if stuck_counter > 0 then
			move_speed = math.min(GHOST_SPEED + stuck_counter * 0.15, 10.0)
		end

		if last_set_x and last_set_y then
			local drift = math.sqrt((cx - last_set_x)^2 + (cy - last_set_y)^2)
			if drift > 5.0 then
				GamePrintImportant("BLOCKED!", "Collision fix")
				reset_ghost_state()
				cooldown = COOLDOWN_MAX
				return
			end
		end

		-- Block any mouse button (1..5) instantly
		for mb = 1, 5 do
			local ok, down = pcall(InputIsMouseButtonDown, mb)
			if ok and down then
				GamePrintImportant("BLOCKED!", "Mouse click")
				reset_ghost_state()
				cooldown = COOLDOWN_MAX
				return
			end
		end

		for jc = 0, 3 do
			for jb = 0, 15 do
				local ok, down = pcall(InputIsJoystickButtonDown, jc, jb)
				if ok and down then
					GamePrintImportant("BLOCKED!", "Controller input")
					reset_ghost_state()
					cooldown = COOLDOWN_MAX
					return
				end
			end
		end

		local dx, dy = 0, 0
		local controls = EntityGetFirstComponentIncludingDisabled(player_entity, "ControlsComponent")
		if controls then
			local ok, val = pcall(ComponentGetValue2, controls, "mButtonDownLeft")
			if ok and val then dx = dx - 1 end
			ok, val = pcall(ComponentGetValue2, controls, "mButtonDownRight")
			if ok and val then dx = dx + 1 end
			ok, val = pcall(ComponentGetValue2, controls, "mButtonDownUp")
			if ok and val then dy = dy - 1 end
			ok, val = pcall(ComponentGetValue2, controls, "mButtonDownDown")
			if ok and val then dy = dy + 1 end
		end
		if dx == 0 and dy == 0 then
			if InputIsKeyDown(KEY_D) then dx = dx + 1 end
			if InputIsKeyDown(KEY_A) then dx = dx - 1 end
			if InputIsKeyDown(KEY_S) then dy = dy + 1 end
			if InputIsKeyDown(KEY_W) then dy = dy - 1 end
		end
		if dx ~= 0 or dy ~= 0 then
			local new_x = cx + dx * move_speed
			local new_y = cy + dy * move_speed

			if type(DoesWorldExistAt) == "function" and not DoesWorldExistAt(new_x - 5, new_y - 5, new_x + 5, new_y + 5) then
				GamePrintImportant("BLOCKED!", "Unloaded chunk")
				reset_ghost_state()
				cooldown = COOLDOWN_MAX
				return
			end

			if is_deeply_stuck(new_x, new_y) then
				new_x, new_y = push_out_of_solid(new_x, new_y)
			end

			EntityApplyTransform(player_entity, new_x, new_y, rot, sx, sy)
			last_set_x = new_x
			last_set_y = new_y
		else
			last_set_x = cx
			last_set_y = cy
		end

		local char_data = EntityGetFirstComponentIncludingDisabled(player_entity, "CharacterDataComponent")
		if char_data then
			pcall(ComponentSetValue2, char_data, "mVelocity", 0, 0)
			pcall(ComponentSetValue2, char_data, "is_on_ground", false)
			pcall(ComponentSetValue2, char_data, "mFlyingTimeLeft", 0)
			pcall(ComponentSetValue2, char_data, "mFlyingTime", 0)
			pcall(ComponentSetValue2, char_data, "mLevitationTimeLeft", 0)
		end

		if controls then
			local action_fields = {
				"mButtonDownFire", "mButtonDownFire2", "mButtonDownKick",
				"mButtonDownInteract", "mButtonDownInventory", "mButtonDownEmote",
				"mButtonDownThrow", "mButtonDownHook",
			}
			for _, field in ipairs(action_fields) do
				pcall(ComponentSetValue2, controls, field, false)
			end
		end
	end
end

function OnWorldPreUpdate() end
function OnModInit() end
function OnModPostInit() end
local debug_last_keys = {}
local last_biome_print = ""
local biome_frame_counter = 0

local function scan_keys(whitelist, is_holding)
    if type(InputIsKeyDown) ~= "function" then return {} end
    local illegal = {}
    for i = 0, 255 do
        local down = InputIsKeyDown(i)
        if down and not (debug_last_keys[i] or false) then
            print("[DEBUG] Key pressed: " .. tostring(i))
            if is_holding and not whitelist[i] then
                illegal[i] = true
            end
        end
        debug_last_keys[i] = down
    end
    return illegal
end

local function print_biome(biome_file, failed)
    biome_frame_counter = biome_frame_counter + 1
    if biome_frame_counter >= 60 then
        biome_frame_counter = 0
        if not failed and biome_file then
            local debug_str = "[DEBUG] Biome: " .. tostring(biome_file)
            if debug_str ~= last_biome_print then
                last_biome_print = debug_str
                print(debug_str)
            end
        else
            print("[DEBUG] Biome: failed")
        end
    end
end

return {
    scan_keys = scan_keys,
    print_biome = print_biome,
}

kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- SOUND CUSTOMIZATION (Plays ONLY when Steam Generator is actively boiling)
-- ============================================================================
local SOUND_CONFIG = {
    ENABLE_SOUND       = true,
    SOUND_NAME         = "kinetica_steam_generator", -- Custom .ogg in sounds/ folder (without .ogg)
    SOUND_FALLBACK     = "fire_small",               -- Built-in fallback sound if custom .ogg is missing
    SOUND_GAIN         = 0.45,                       -- Volume (0.0 to 1.0)
    SOUND_PITCH        = 1.00,                       -- Base playback pitch
    PITCH_JITTER       = 0.08,                       -- Slight random pitch variation (+/-)
    SOUND_INTERVAL     = 0.03,                       -- Seconds between sound triggers while active
    MAX_HEAR_DISTANCE  = 16,                         -- Max distance (blocks) players can hear it
}

local CONFIG = {
    WATER_BOIL_DURATION           = 20,
    WATER_USE_PER_SEC             = 10,
    STEAM_OUT_PER_SEC             = 30,
    MAX_WATER_LEVEL               = 100,
    ANIM_LENGTH                   = 0.35,
    LIGHT_SOURCE_ACTIVE           = 12,
    SPAWN_FRONT_EMBERS            = true,
    ENABLE_UNDER_HEAT_BONUS       = true,
    UNDER_HEAT_FUEL_SAVER_CHANCE  = 0.25,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    UI_COLORS = {
        BG_WINDOW      = "#14171D",
        BG_HEADER      = "#1F242D",
        BG_CARD        = "#1B2028",
        BG_INV_PANEL   = "#171B22",
        BG_BAR_TROUGH  = "#0E1015",
        ACCENT_ACTIVE  = "#FF6D00",
        ACCENT_IDLE    = "#F5B041",
        ACCENT_WATER   = "#00B0FF",
        ACCENT_FUEL    = "#FF5252",
        ACCENT_STEAM   = "#E0E0E0",
        TEXT_TITLE     = "#F5B041",
        TEXT_SUBTITLE  = "#ABB2B9",
        TEXT_LABEL     = "#95A5A6",
        TEXT_VALUE     = "#FFFFFF",
        TEXT_OK        = "#00E676",
        TEXT_WARN      = "#FFB300",
    },
    TEX_TOP                       = "kinetica_steam_maker_top.png",
    TEX_BOTTOM                    = "kinetica_steam_maker_down.png",
    TEX_SIDE                      = "kinetica_steam_maker_side.png",
    TEX_FRONT_OFF                 = "kinetica_steam_maker_front_off.png",
    TEX_FRONT_ANIM                = "kinetica_steam_maker_aniamtion.png",
}

local IDLE_NAME   = "kinetica:steam_generator"
local ACTIVE_NAME = "kinetica:steam_generator_active"

local WATER_BOIL_DURATION = CONFIG.WATER_BOIL_DURATION
local WATER_USE_PER_SEC   = CONFIG.WATER_USE_PER_SEC
local STEAM_OUT_PER_SEC   = CONFIG.STEAM_OUT_PER_SEC

local function resolve_sound_name(cfg)
    if cfg.SOUND_NAME and cfg.SOUND_NAME ~= "" then
        local f = io.open(modpath .. "/sounds/" .. cfg.SOUND_NAME .. ".ogg", "r")
        if f then
            f:close()
            return cfg.SOUND_NAME
        end
    end
    if cfg.SOUND_FALLBACK and cfg.SOUND_FALLBACK ~= "" then
        return cfg.SOUND_FALLBACK
    end
    return cfg.SOUND_NAME
end

local RESOLVED_SOUND = resolve_sound_name(SOUND_CONFIG)

local function play_steam_gen_active_sound(pos, meta, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not RESOLVED_SOUND or RESOLVED_SOUND == "" then
        return
    end
    local acc = meta:get_float("sfx_timer") + (dt or 1.0)
    if acc < (SOUND_CONFIG.SOUND_INTERVAL or 1.0) then
        meta:set_float("sfx_timer", acc)
        return
    end
    meta:set_float("sfx_timer", 0)

    local jitter = (SOUND_CONFIG.PITCH_JITTER or 0) * ((math.random() * 2.0) - 1.0)
    local pitch  = math.max(0.2, (SOUND_CONFIG.SOUND_PITCH or 1.0) + jitter)

    core.sound_play(RESOLVED_SOUND, {
        pos               = pos,
        gain              = SOUND_CONFIG.SOUND_GAIN or 0.45,
        pitch             = pitch,
        max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 16,
    }, true)
end

function kinetica.is_steam_generator(name)
    return name == IDLE_NAME or name == ACTIVE_NAME
end

local function is_water_bucket(name)
    return name == "mcl_buckets:bucket_water" or name == "mcl_buckets:bucket_river_water"
end

local function has_under_heat_bonus(pos)
    if not CONFIG.ENABLE_UNDER_HEAT_BONUS then return false end
    local bnode = core.get_node({x = pos.x, y = pos.y - 1, z = pos.z})
    local bname = bnode.name or ""
    if core.get_item_group(bname, "lava") > 0 or
       core.get_item_group(bname, "fire") > 0 or
       bname == "mcl_nether:magma" or
       string.find(bname, "campfire") then
        return true
    end
    return false
end

local function C(hex, text)
    return core.colorize(hex, tostring(text))
end

function kinetica.get_steam_gen_formspec(burn_percent, water_level, show_water_block_icon)
    local U         = CONFIG.UI_COLORS
    local burn_pct  = math.min(100, math.max(0, math.floor(burn_percent or 0)))
    local water_pct = math.min(100, math.max(0, math.floor(water_level or 0)))
    local is_boiling= (burn_pct > 0 and water_pct > 0)

    local flame_img = "default_furnace_fire_bg.png"
    if burn_pct > 0 then
        flame_img = "default_furnace_fire_bg.png^[lowpart:" ..
                    burn_pct .. ":default_furnace_fire_fg.png"
    end

    local water_icon = ""
    if show_water_block_icon then
        water_icon = "item_image[1.55,1.85;1,1;mcl_core:water_source]"
    end

    local status_str
    local header_accent = U.ACCENT_IDLE
    if is_boiling then
        header_accent = U.ACCENT_ACTIVE
        status_str = C(U.TEXT_OK, string.format(
            "BOILING — Producing %d Steam/s out Top Port  |  Water: %d%%  |  Fuel: %d%%",
            STEAM_OUT_PER_SEC, water_pct, burn_pct
        ))
    elseif water_pct <= 0 then
        status_str = C(U.TEXT_WARN, "WAITING FOR WATER — Connect Water Pipe to Sides/Bottom or Insert Bucket")
    else
        status_str = C(U.TEXT_WARN, string.format("IDLE (Water: %d%%) — Add Coal/Fuel to Ignite Firebox", water_pct))
    end

    local water_bar_w = math.max(0.05, (water_pct / 100) * 2.5)
    local fuel_bar_w  = math.max(0.05, (burn_pct / 100) * 2.5)

    local slot_bg_water = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(1.55, 1.85, 1, 1) or ""
    local slot_bg_fuel  = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(4.40, 2.35, 1, 1) or ""
    local inv_bg_1      = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0.4,  4.55, 9, 3) or ""
    local inv_bg_2      = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0.4,  7.70, 9, 1) or ""

    local fs = {
        "size[9.8,8.8]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;9.8,1.05;" .. U.BG_HEADER .. "]",
        "box[0,1.02;9.8,0.05;" .. header_accent .. "]",
        "label[0.3,0.12;" .. C(U.TEXT_TITLE, "HIGH-PRESSURE STEAM GENERATOR") .. "]",
        "label[0.3,0.52;" .. status_str .. "]",
        "box[0.25,1.25;2.9,2.85;" .. U.BG_CARD .. "]",
        "box[0.25,1.25;0.07,2.85;" .. U.ACCENT_WATER .. "]",
        "label[0.45,1.35;" .. C(U.ACCENT_WATER, "WATER TANK (" .. water_pct .. "%)") .. "]",
        slot_bg_water,
        water_icon,
        "list[context;water;1.55,1.85;1,1;]",
        "label[0.45,2.05;" .. C(U.TEXT_LABEL, "Bucket /") .. "]",
        "label[0.45,2.38;" .. C(U.TEXT_LABEL, "Pipe In") .. "]",
        "box[0.45,3.15;2.5,0.28;" .. U.BG_BAR_TROUGH .. "]",
        "box[0.45,3.15;" .. string.format("%.2f", water_bar_w) .. ",0.28;" .. U.ACCENT_WATER .. "]",
        "label[0.45,3.55;" .. C(U.TEXT_LABEL, string.format("Uses %d Water/s", WATER_USE_PER_SEC)) .. "]",
        "box[3.40,1.25;3.0,2.85;" .. U.BG_CARD .. "]",
        "box[3.40,1.25;0.07,2.85;" .. U.ACCENT_FUEL .. "]",
        "label[3.60,1.35;" .. C(U.ACCENT_FUEL, "FIREBOX (" .. burn_pct .. "%)") .. "]",
        "image[4.40,1.45;0.9,0.9;" .. flame_img .. "]",
        slot_bg_fuel,
        "list[context;fuel;4.40,2.35;1,1;]",
        "box[3.60,3.48;2.5,0.22;" .. U.BG_BAR_TROUGH .. "]",
        "box[3.60,3.48;" .. string.format("%.2f", fuel_bar_w) .. ",0.22;" .. U.ACCENT_FUEL .. "]",
        "label[3.60,3.72;" .. C(U.TEXT_LABEL, "Coal / Wood / Lava") .. "]",
        "box[6.65,1.25;2.9,2.85;" .. U.BG_CARD .. "]",
        "box[6.65,1.25;0.07,2.85;" .. U.ACCENT_STEAM .. "]",
        "label[6.85,1.35;" .. C(U.ACCENT_STEAM, "STEAM OUTPUT (TOP)") .. "]",
        "label[6.85,1.90;" .. C(U.TEXT_LABEL, "Output Rate:") .. "]",
        "label[6.85,2.28;" .. C(U.TEXT_VALUE, string.format("%d Steam / sec", is_boiling and STEAM_OUT_PER_SEC or 0)) .. "]",
        "label[6.85,2.85;" .. C(U.TEXT_LABEL, "Water Ports:") .. " " .. C(U.TEXT_VALUE, "Sides/Bot") .. "]",
        "label[6.85,3.25;" .. C(U.TEXT_LABEL, "Steam Port:") .. "  " .. C(U.TEXT_VALUE, "Top (+Y)") .. "]",
        "box[0.25,4.22;9.3,4.45;" .. U.BG_INV_PANEL .. "]",
        "label[0.40,4.22;" .. C(U.TEXT_SUBTITLE, "Player Inventory") .. "]",
        "list[current_player;main;0.4,4.55;9,3;9]",
        inv_bg_1,
        "list[current_player;main;0.4,7.70;9,1;]",
        inv_bg_2,
        "listring[current_player;main]",
        "listring[context;water]",
        "listring[current_player;main]",
        "listring[context;fuel]",
    }
    return table.concat(fs)
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local function format_steam_gen_glasses_info(pos, node)
    local meta            = core.get_meta(pos)
    local inv             = meta:get_inventory()
    local burn_time       = meta:get_float("burn_time")
    local max_burn        = math.max(1, meta:get_float("max_burn"))
    local water_boil_time = meta:get_float("water_boil_time")
    local piped_water     = meta:get_int("water_level")
    local water_stack     = inv and inv:get_stack("water", 1) or ItemStack("")
    local fuel_stack      = inv and inv:get_stack("fuel", 1) or ItemStack("")

    local has_bucket      = is_water_bucket(water_stack:get_name())
    local display_water   = has_bucket
        and ((water_boil_time > 0) and math.floor((water_boil_time / WATER_BOIL_DURATION) * 100) or 100)
        or  piped_water
    local burn_pct        = (burn_time > 0) and math.min(100, math.floor((burn_time / max_burn) * 100)) or 0
    local is_boiling      = (node.name == ACTIVE_NAME) or (burn_time > 0 and (has_bucket or piped_water >= WATER_USE_PER_SEC))

    local state_str = "IDLE (Add Fuel)"
    if is_boiling then
        state_str = "BOILING STEAM"
    elseif not has_bucket and piped_water < WATER_USE_PER_SEC then
        state_str = "WAITING FOR WATER"
    end

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Machine:    Steam Generator",
        "State:      " .. state_str,
        string.format("Water Tank: %d%% (%s)", display_water, has_bucket and "Water Bucket" or "Piped Water"),
        string.format("Firebox:    %d%% Burn Remaining (Fuel: %d)", burn_pct, fuel_stack:get_count()),
        string.format("Steam Out:  %d Steam/s (Top Port)", is_boiling and STEAM_OUT_PER_SEC or 0),
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME]   = format_steam_gen_glasses_info
kinetica._glasses_formatters[ACTIVE_NAME] = format_steam_gen_glasses_info

local function spawn_front_firebox_embers(pos, param2)
    if not CONFIG.SPAWN_FRONT_EMBERS then return end
    local back_dir  = core.facedir_to_dir((param2 or 0) % 4) or {x = 0, y = 0, z = 1}
    local front_dir = {x = -back_dir.x, y = 0, z = -back_dir.z}
    local fpos = {
        x = pos.x + front_dir.x * 0.54,
        y = pos.y - 0.12,
        z = pos.z + front_dir.z * 0.54,
    }
    core.add_particlespawner({
        amount             = 3,
        time               = 1.0,
        minpos             = {x = fpos.x - 0.18, y = fpos.y - 0.12, z = fpos.z - 0.18},
        maxpos             = {x = fpos.x + 0.18, y = fpos.y + 0.12, z = fpos.z + 0.18},
        minvel             = {x = front_dir.x * 0.05 - 0.05, y = 0.15, z = front_dir.z * 0.05 - 0.05},
        maxvel             = {x = front_dir.x * 0.18 + 0.05, y = 0.40, z = front_dir.z * 0.18 + 0.05},
        minexptime         = 0.25,
        maxexptime         = 0.55,
        minsize            = 0.9,
        maxsize            = 1.6,
        collisiondetection = false,
        glow               = 13,
        texture            = "bubble.png^[colorize:#ff5500:230",
    })
end

local function steam_generator_timer(pos, elapsed)
    local meta = core.get_meta(pos)
    local inv  = meta:get_inventory()
    local node = core.get_node(pos)
    local burn_time       = meta:get_float("burn_time")
    local max_burn        = meta:get_float("max_burn")
    local water_boil_time = meta:get_float("water_boil_time")
    local piped_water     = meta:get_int("water_level")
    local water_stack     = inv:get_stack("water", 1)
    local has_bucket_water= is_water_bucket(water_stack:get_name())
    local has_any_water   = has_bucket_water or (piped_water >= WATER_USE_PER_SEC)
    local show_water_icon = (piped_water > 0) and water_stack:is_empty()

    if not has_any_water then
        meta:set_float("water_boil_time", 0)
        meta:set_int("steam_out_rate", 0)
        meta:set_float("sfx_timer", 0)
        if node.name == ACTIVE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
            node.name = IDLE_NAME
        end
        local percent       = (burn_time > 0 and max_burn > 0) and ((burn_time / max_burn) * 100) or 0
        local display_water = has_bucket_water and 100 or piped_water
        meta:set_int("display_water", display_water)
        meta:set_int("burn_pct", math.floor(percent))
        if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", string.format("Steam Generator: Waiting for Water (Water: %d%%)", display_water))
        end
        meta:set_string("formspec", kinetica.get_steam_gen_formspec(percent, display_water, show_water_icon))
        meta:set_string("glasses_info", format_steam_gen_glasses_info(pos, node))
        return false
    end

    if burn_time <= 0 then
        local fuel_stack = inv:get_stack("fuel", 1)
        local fuel_output, decremented_fuel = core.get_craft_result({
            method = "fuel",
            width  = 1,
            items  = {fuel_stack},
        })
        if fuel_output.time > 0 then
            burn_time = fuel_output.time
            max_burn  = fuel_output.time
            meta:set_float("burn_time", burn_time)
            meta:set_float("max_burn", max_burn)
            if not fuel_output.item:is_empty() and decremented_fuel.items[1]:is_empty() then
                inv:set_stack("fuel", 1, ItemStack("mcl_buckets:bucket_empty 1"))
            else
                inv:set_stack("fuel", 1, decremented_fuel.items[1])
            end
            if has_bucket_water and water_boil_time <= 0 then
                water_boil_time = WATER_BOIL_DURATION
                meta:set_float("water_boil_time", water_boil_time)
            end
        end
    end

    if burn_time > 0 and has_any_water then
        if not (has_under_heat_bonus(pos) and math.random() < CONFIG.UNDER_HEAT_FUEL_SAVER_CHANCE) then
            burn_time = burn_time - 1
            meta:set_float("burn_time", burn_time)
        end
        if piped_water >= WATER_USE_PER_SEC then
            piped_water = piped_water - WATER_USE_PER_SEC
            meta:set_int("water_level", piped_water)
        elseif has_bucket_water then
            if water_boil_time <= 0 then
                water_boil_time = WATER_BOIL_DURATION
            end
            water_boil_time = water_boil_time - 1
            meta:set_float("water_boil_time", water_boil_time)
            if water_boil_time <= 0 then
                inv:set_stack("water", 1, ItemStack("mcl_buckets:bucket_empty 1"))
            end
        end
        if node.name == IDLE_NAME then
            core.swap_node(pos, {name = ACTIVE_NAME, param2 = node.param2})
            node.name = ACTIVE_NAME
        end

        -- Play sound ONLY while actively boiling steam
        play_steam_gen_active_sound(pos, meta, 1.0)
        spawn_front_firebox_embers(pos, node.param2)

        local percent       = (burn_time / math.max(1, max_burn)) * 100
        local display_water = has_bucket_water and math.floor((water_boil_time / WATER_BOIL_DURATION) * 100) or piped_water
        show_water_icon     = (piped_water > 0) and inv:get_stack("water", 1):is_empty()

        meta:set_int("display_water", display_water)
        meta:set_int("burn_pct", math.floor(percent))
        meta:set_int("steam_out_rate", STEAM_OUT_PER_SEC)

        if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", string.format(
                "Steam Generator: BOILING (Water: %d%% | Fuel: %d%% -> %d Steam/s)",
                display_water, math.floor(percent), STEAM_OUT_PER_SEC
            ))
        end
        meta:set_string("formspec", kinetica.get_steam_gen_formspec(percent, display_water, show_water_icon))
        meta:set_string("glasses_info", format_steam_gen_glasses_info(pos, node))

        local top_pos = {x = pos.x, y = pos.y + 1, z = pos.z}
        if kinetica.can_pipe_accept and kinetica.can_pipe_accept(top_pos, "steam") then
            kinetica.add_fluid_to_pipe(top_pos, "steam", STEAM_OUT_PER_SEC)
        else
            core.add_particlespawner({
                amount     = 6,
                time       = 1.0,
                minpos     = {x = pos.x - 0.1, y = pos.y + 0.55, z = pos.z - 0.1},
                maxpos     = {x = pos.x + 0.1, y = pos.y + 0.65, z = pos.z + 0.1},
                minvel     = {x = -0.1, y = 0.6, z = -0.1},
                maxvel     = {x =  0.1, y = 1.2, z =  0.1},
                minexptime = 1.0,
                maxexptime = 2.0,
                minsize    = 1.5,
                maxsize    = 3.0,
                texture    = "mcl_particles_smoke.png",
            })
        end
        return true
    else
        meta:set_int("steam_out_rate", 0)
        meta:set_float("sfx_timer", 0)
        if node.name == ACTIVE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
            node.name = IDLE_NAME
        end
        local display_water = has_bucket_water and 100 or piped_water
        show_water_icon     = (piped_water > 0) and inv:get_stack("water", 1):is_empty()
        meta:set_int("display_water", display_water)
        meta:set_int("burn_pct", 0)
        if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", string.format("Steam Generator: Idle (Water: %d%% - Add Fuel)", display_water))
        end
        meta:set_string("formspec", kinetica.get_steam_gen_formspec(0, display_water, show_water_icon))
        meta:set_string("glasses_info", format_steam_gen_glasses_info(pos, node))
        return false
    end
end

local common_Callbacks = {
    paramtype2 = "facedir",
    on_place = core.rotate_and_place,
    _mcl_hardness = 3.5,
    _mcl_blast_resistance = 3.5,
    sounds = mcl_sounds.node_sound_stone_defaults(),

    on_construct = function(pos)
        local meta = core.get_meta(pos)
        local inv  = meta:get_inventory()
        inv:set_size("water", 1)
        inv:set_size("fuel", 1)
        meta:set_int("water_level", 0)
        meta:set_int("display_water", 0)
        meta:set_int("burn_pct", 0)
        meta:set_int("steam_out_rate", 0)
        meta:set_float("sfx_timer", 0)
        meta:set_string("infotext", "Steam Generator: Idle (Connect Water Pipe to Sides/Bottom | Steam Out on Top)")
        meta:set_string("formspec", kinetica.get_steam_gen_formspec(0, 0, false))
        meta:set_string("glasses_info", format_steam_gen_glasses_info(pos, core.get_node(pos)))
    end,

    on_timer = steam_generator_timer,

    allow_metadata_inventory_put = function(pos, listname, index, stack, player)
        if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
            return 0
        end
        local inv = core.get_meta(pos):get_inventory()
        if listname == "water" then
            if is_water_bucket(stack:get_name()) and inv:get_stack("water", 1):is_empty() then
                return 1
            end
            return 0
        elseif listname == "fuel" then
            local fuel_res = core.get_craft_result({method = "fuel", width = 1, items = {stack}})
            if fuel_res.time > 0 then
                return stack:get_count()
            end
            return 0
        end
        return 0
    end,

    on_metadata_inventory_put = function(pos)
        core.get_node_timer(pos):start(1.0)
    end,
    on_metadata_inventory_take = function(pos)
        core.get_node_timer(pos):start(1.0)
    end,

    after_dig_node = function(pos, oldnode, oldmetadata, digger)
        if oldmetadata and oldmetadata.inventory then
            for _, listname in ipairs({"water", "fuel"}) do
                local list = oldmetadata.inventory[listname]
                if list then
                    for _, item in ipairs(list) do
                        if not item:is_empty() then
                            core.add_item(pos, item)
                        end
                    end
                end
            end
        end
    end,

    _on_hopper_in = function(hopper_pos, to_pos)
        local h_inv = core.get_meta(hopper_pos):get_inventory()
        local g_inv = core.get_meta(to_pos):get_inventory()

        for i = 1, h_inv:get_size("main") do
            local stack = h_inv:get_stack("main", i)
            if not stack:is_empty() then
                local name = stack:get_name()
                if is_water_bucket(name) and g_inv:get_stack("water", 1):is_empty() then
                    g_inv:set_stack("water", 1, ItemStack(name .. " 1"))
                    stack:take_item(1)
                    h_inv:set_stack("main", i, stack)
                    core.get_node_timer(to_pos):start(1.0)
                    return true
                end
                local fuel_res = core.get_craft_result({method = "fuel", width = 1, items = {stack}})
                if fuel_res.time > 0 then
                    local single_fuel = ItemStack(name .. " 1")
                    if g_inv:room_for_item("fuel", single_fuel) then
                        g_inv:add_item("fuel", single_fuel)
                        stack:take_item(1)
                        h_inv:set_stack("main", i, stack)
                        core.get_node_timer(to_pos):start(1.0)
                        return true
                    end
                end
            end
        end
        return false
    end,

    _on_hopper_out = function(from_pos, to_hopper_pos)
        local g_inv = core.get_meta(from_pos):get_inventory()
        local h_inv = core.get_meta(to_hopper_pos):get_inventory()

        for _, slot_name in ipairs({"water", "fuel"}) do
            local stack = g_inv:get_stack(slot_name, 1)
            if stack:get_name() == "mcl_buckets:bucket_empty" then
                local single_bucket = ItemStack("mcl_buckets:bucket_empty 1")
                if h_inv:room_for_item("main", single_bucket) then
                    h_inv:add_item("main", single_bucket)
                    stack:take_item(1)
                    g_inv:set_stack(slot_name, 1, stack)
                    core.get_node_timer(from_pos):start(1.0)
                    return true
                end
            end
        end
        return false
    end,
}

core.register_node(IDLE_NAME, {
    description = "Steam Generator (Water In: Sides/Bottom | Steam Out: Top)",
    tiles = {
        CONFIG.TEX_TOP,
        CONFIG.TEX_BOTTOM,
        CONFIG.TEX_SIDE,
        CONFIG.TEX_SIDE,
        CONFIG.TEX_SIDE,
        CONFIG.TEX_FRONT_OFF,
    },
    groups = {pickaxey = 2, container = 2, steam_connectable = 1, pipe_water = 1, pipe_steam = 1, kinetica_steam_gen = 1},
    paramtype2 = common_Callbacks.paramtype2,
    on_place = common_Callbacks.on_place,
    _mcl_hardness = common_Callbacks._mcl_hardness,
    _mcl_blast_resistance = common_Callbacks._mcl_blast_resistance,
    sounds = common_Callbacks.sounds,
    on_construct = common_Callbacks.on_construct,
    on_timer = common_Callbacks.on_timer,
    allow_metadata_inventory_put = common_Callbacks.allow_metadata_inventory_put,
    on_metadata_inventory_put = common_Callbacks.on_metadata_inventory_put,
    on_metadata_inventory_take = common_Callbacks.on_metadata_inventory_take,
    after_dig_node = common_Callbacks.after_dig_node,
    _on_hopper_in = common_Callbacks._on_hopper_in,
    _on_hopper_out = common_Callbacks._on_hopper_out,
})

core.register_node(ACTIVE_NAME, {
    description = "Steam Generator",
    tiles = {
        CONFIG.TEX_TOP,
        CONFIG.TEX_BOTTOM,
        CONFIG.TEX_SIDE,
        CONFIG.TEX_SIDE,
        CONFIG.TEX_SIDE,
        {
            name = CONFIG.TEX_FRONT_ANIM,
            animation = {
                type     = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length   = CONFIG.ANIM_LENGTH,
            },
        },
    },
    light_source = CONFIG.LIGHT_SOURCE_ACTIVE,
    drop = IDLE_NAME,
    groups = {pickaxey = 2, container = 2, not_in_creative_inventory = 1, steam_connectable = 1, pipe_water = 1, pipe_steam = 1, kinetica_steam_gen = 1},
    paramtype2 = common_Callbacks.paramtype2,
    _mcl_hardness = common_Callbacks._mcl_hardness,
    _mcl_blast_resistance = common_Callbacks._mcl_blast_resistance,
    sounds = common_Callbacks.sounds,
    on_construct = common_Callbacks.on_construct,
    on_timer = common_Callbacks.on_timer,
    allow_metadata_inventory_put = common_Callbacks.allow_metadata_inventory_put,
    on_metadata_inventory_put = common_Callbacks.on_metadata_inventory_put,
    on_metadata_inventory_take = common_Callbacks.on_metadata_inventory_take,
    after_dig_node = common_Callbacks.after_dig_node,
    _on_hopper_in = common_Callbacks._on_hopper_in,
    _on_hopper_out = common_Callbacks._on_hopper_out,
})

core.register_lbm({
    label             = "Refresh kinetica Steam Generators on chunk load",
    name              = "kinetica:refresh_steam_gen_lbm",
    nodenames         = {"group:kinetica_steam_gen"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(1.0)
        end
    end,
})

core.register_craft({
    output = "kinetica:steam_generator",
    recipe = {
        {"",                        "kinetica:sheet_copper", ""},
        {"kinetica:copper_casing",  "mcl_furnaces:furnace",  "kinetica:copper_casing"},
        {"",                        "mcl_buckets:bucket_empty", ""},
    },
})
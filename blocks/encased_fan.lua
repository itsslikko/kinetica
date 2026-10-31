kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- SOUND CUSTOMIZATION (Plays ONLY when Encased Fan is actively spinning)
-- ============================================================================
local SOUND_CONFIG = {
    ENABLE_SOUND         = true,
    SOUND_NAME           = "kinetica_encased_fan", -- Custom .ogg in sounds/ folder (without .ogg)
    SOUND_FALLBACK       = "default_cool_lava",    -- Built-in fallback sound if custom .ogg is missing
    SOUND_GAIN           = 0.22,                   -- Volume (0.0 to 1.0)
    SOUND_PITCH          = 0.90,                   -- Base pitch when SCALE_PITCH_WITH_RPM = false
    SCALE_PITCH_WITH_RPM = true,                   -- Scale pitch dynamically with shaft RPM
    MIN_PITCH            = 0.70,                   -- Pitch at MIN_RPM (16 RPM)
    MAX_PITCH            = 1.40,                   -- Pitch at 512+ RPM
    SOUND_INTERVAL       = 0.01,                   -- Seconds between sound triggers while active
    MAX_HEAR_DISTANCE    = 14,                     -- Max distance (blocks) players can hear it
}

local CONFIG = {
    NOZZLE_FACES_PLAYER           = true,
    CW_ROTATION_PUSHES            = true,
    MIN_RPM                       = 16,
    KU_PER_RPM                    = 2,
    MIN_KU                        = 32,
    MAX_KU                        = 128,
    MAX_RPM_CAP                   = 3072,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
        { name = "ultra",  max_rpm = 3072, length = 0.03 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TICK_INTERVAL                 = 0.20,
    RANGE_AT_MIN_RPM              = 3,
    RANGE_AT_512_RPM              = 14,
    ITEM_SPEED_AT_MIN_RPM         = 1.2,
    ITEM_SPEED_AT_512_RPM         = 7.5,
    PARTICLE_SPEED_AT_MIN_RPM     = 2.5,
    PARTICLE_SPEED_AT_512_RPM     = 9.5,
    PUSH_PLAYERS_AND_MOBS         = true,
    ENTITY_SPEED_AT_MIN_RPM       = 1.8,
    ENTITY_SPEED_AT_512_RPM       = 5.5,
    ENABLE_BULK_PROCESS           = true,
    PROCESS_TIME_AT_MIN_RPM       = 4.5,
    PROCESS_TIME_AT_512_RPM       = 0.8,
    SCALE_TIME_BY_STACK_SIZE      = true,
    CATALYST_DAMAGE_INTERVAL      = 1.0,
    TEX_FAN_FRONT                 = "kinetica_encased_fan_front.png",
    TEX_FAN_BACK                  = "kinetica_encased_fan_back.png",
    TEX_FAN_SIDE                  = "kinetica_andisite_casing.png",
    TEX_FALLBACK_FRONT            = "mcl_stonecutter_top.png",
    TEX_FALLBACK_BACK             = "kinetica_chain_drive_front.png",
    TEX_FALLBACK_SIDE             = "kinetica_chain_drive_side.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME  = "kinetica:encased_fan"
local ACT_CW     = "kinetica:encased_fan_active_cw"
local ACT_CCW    = "kinetica:encased_fan_active_ccw"
local CHUTE_NAME = "kinetica:chute"
local DEPOT_NAME = "kinetica:depot"

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

local function play_fan_active_sound(pos, meta, rpm, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not RESOLVED_SOUND or RESOLVED_SOUND == "" then
        return
    end

    local acc = meta:get_float("sfx_timer") + (dt or CONFIG.TICK_INTERVAL)
    if acc < (SOUND_CONFIG.SOUND_INTERVAL or 1.20) then
        meta:set_float("sfx_timer", acc)
        return
    end
    meta:set_float("sfx_timer", 0)

    local pitch = SOUND_CONFIG.SOUND_PITCH or 0.90
    if SOUND_CONFIG.SCALE_PITCH_WITH_RPM then
        local t = math.min(1.0, math.max(0.0, ((rpm or CONFIG.MIN_RPM) - CONFIG.MIN_RPM) / (512 - CONFIG.MIN_RPM)))
        local min_p = SOUND_CONFIG.MIN_PITCH or 0.70
        local max_p = SOUND_CONFIG.MAX_PITCH or 1.40
        pitch = min_p + t * (max_p - min_p)
    end

    core.sound_play(RESOLVED_SOUND, {
        pos               = pos,
        gain              = SOUND_CONFIG.SOUND_GAIN or 0.22,
        pitch             = pitch,
        max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 14,
    }, true)
end

local function is_fan_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_encased_fan = is_fan_node

local function file_exists(filename)
    local f = io.open(modpath .. "/textures/" .. filename, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local TEX_FRONT = file_exists(CONFIG.TEX_FAN_FRONT) and CONFIG.TEX_FAN_FRONT or CONFIG.TEX_FALLBACK_FRONT
local TEX_BACK  = file_exists(CONFIG.TEX_FAN_BACK)  and CONFIG.TEX_FAN_BACK  or CONFIG.TEX_FALLBACK_BACK
local TEX_SIDE  = file_exists(CONFIG.TEX_FAN_SIDE)  and CONFIG.TEX_FAN_SIDE  or CONFIG.TEX_FALLBACK_SIDE

local function rpm_factor(rpm)
    if not rpm or rpm <= CONFIG.MIN_RPM then return 0.0 end
    return math.min(1.0, math.max(0.0, (rpm - CONFIG.MIN_RPM) / (512 - CONFIG.MIN_RPM)))
end

local function lerp(a, b, t)
    return a + t * (b - a)
end

local function get_fan_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then
        return CONFIG.MIN_KU
    end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local function get_airflow_range(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0 end
    return math.floor(lerp(CONFIG.RANGE_AT_MIN_RPM, CONFIG.RANGE_AT_512_RPM, rpm_factor(rpm)) + 0.5)
end

local function get_item_speed(rpm)
    return lerp(CONFIG.ITEM_SPEED_AT_MIN_RPM, CONFIG.ITEM_SPEED_AT_512_RPM, rpm_factor(rpm))
end

local function get_entity_speed(rpm)
    return lerp(CONFIG.ENTITY_SPEED_AT_MIN_RPM, CONFIG.ENTITY_SPEED_AT_512_RPM, rpm_factor(rpm))
end

local function get_particle_speed(rpm)
    return lerp(CONFIG.PARTICLE_SPEED_AT_MIN_RPM, CONFIG.PARTICLE_SPEED_AT_512_RPM, rpm_factor(rpm))
end

local function get_process_time(rpm, stack_count)
    local base = lerp(CONFIG.PROCESS_TIME_AT_MIN_RPM, CONFIG.PROCESS_TIME_AT_512_RPM, rpm_factor(rpm))
    if CONFIG.SCALE_TIME_BY_STACK_SIZE and stack_count and stack_count > 16 then
        local mult = math.min(4, math.ceil(stack_count / 16))
        return base * mult
    end
    return base
end

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_active_fan_node_name(rpm, spin_dir)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (spin_dir == 1) and "cw" or "ccw"
    local candidate = IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then
        return candidate
    end
    return (spin_dir == 1) and ACT_CW or ACT_CCW
end

local AXIS_TO_FAN_DIR = {
    [0] = {x =  0, y =  1, z =  0},
    [1] = {x =  0, y =  0, z =  1},
    [2] = {x =  0, y =  0, z = -1},
    [3] = {x =  1, y =  0, z =  0},
    [4] = {x = -1, y =  0, z =  0},
    [5] = {x =  0, y = -1, z =  0},
}

local function get_fan_dir(param2)
    local axisdir = math.floor(((param2 or 0) % 24) / 4)
    local d = AXIS_TO_FAN_DIR[axisdir] or AXIS_TO_FAN_DIR[0]
    return {x = d.x, y = d.y, z = d.z}
end

local function get_back_dir(param2)
    local f = get_fan_dir(param2)
    return {x = -f.x, y = -f.y, z = -f.z}
end

local function dir_to_name(d)
    if d.y > 0 then return "up"
    elseif d.y < 0 then return "down"
    elseif d.x > 0 then return "east"
    elseif d.x < 0 then return "west"
    elseif d.z > 0 then return "north"
    else return "south" end
end

local function get_flipped_fan_param2(fan_dir)
    local axisdir = 0
    if fan_dir.y > 0 then
        axisdir = 0
    elseif fan_dir.y < 0 then
        axisdir = 5
    elseif fan_dir.z > 0 then
        axisdir = 1
    elseif fan_dir.z < 0 then
        axisdir = 2
    elseif fan_dir.x > 0 then
        axisdir = 3
    elseif fan_dir.x < 0 then
        axisdir = 4
    end

    if axisdir >= 1 and axisdir <= 4 then
        for rot = 0, 3 do
            local p2 = axisdir * 4 + rot
            local zdir = core.facedir_to_dir(p2)
            if zdir and zdir.y == 1 then
                return p2
            end
        end
    end
    return axisdir * 4
end

local function look_to_unit_dir(placer)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if ay > ax and ay > az then
        return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then
        return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else
        return {x = 0, y = 0, z = (look.z > 0) and 1 or -1}
    end
end

local function place_encased_fan(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end

    local under_pos  = pointed_thing.under
    local above_pos  = pointed_thing.above
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local diff = {
        x = above_pos.x - under_pos.x,
        y = above_pos.y - under_pos.y,
        z = above_pos.z - under_pos.z,
    }

    local fan_dir = nil

    if not sneaking then
        if (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff, under_pos)) or
           (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(under_node.name)) or
           under_node.name == "kinetica:piston_head" or
           under_node.name == "kinetica:piston_head_sticky" then
            fan_dir = diff
        elseif under_node.name == CHUTE_NAME and diff.y == -1 then
            fan_dir = {x = 0, y = 1, z = 0}
        end
    end

    if not fan_dir then
        local ldir = look_to_unit_dir(placer)
        local invert = CONFIG.NOZZLE_FACES_PLAYER
        if sneaking then invert = not invert end
        if invert then
            fan_dir = {x = -ldir.x, y = -ldir.y, z = -ldir.z}
        else
            fan_dir = ldir
        end
    end

    local param2 = get_flipped_fan_param2(fan_dir)
    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)

    if place_pos then
        local meta = core.get_meta(place_pos)
        meta:set_int("invert_dir", 0)
        meta:set_string("active", "false")
        meta:set_string("airflow_dir", "none")
        meta:set_int("is_pull", 0)
        meta:set_float("sfx_timer", 0)
    end
    return placed_stack
end

local function make_fan_back_idle()
    return "[combine:16x16:0,0=" .. TEX_BACK .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
end

local function make_fan_back_anim(reverse, anim_length)
    local bg = TEX_BACK
    local ov = CONFIG.TEX_SHAFT_OVERLAY

    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip = ov
    if reverse then
        ov_strip = "[combine:16x64" ..
            ":0,0="  .. ov .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    end
    return {
        name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.24,
        },
    }
end

local back_idle = make_fan_back_idle()

local CATALYST_PRIORITY = {
    washing  = 1,
    freezing = 2,
    smoking  = 3,
    haunting = 4,
    blasting = 5,
}

local function classify_stream_node(node_name, fan_dir)
    if node_name == "air" then
        return true, nil
    end
    if node_name == "ignore" then
        return false, nil
    end

    if (kinetica.is_funnel and kinetica.is_funnel(node_name)) or
       core.get_item_group(node_name, "kinetica_funnel") > 0 then
        return false, nil
    end

    if node_name == DEPOT_NAME or
       core.get_item_group(node_name, "kinetica_depot") > 0 or
       core.get_item_group(node_name, "mechanical_belt") > 0 then
        return true, nil
    end

    if (node_name == CHUTE_NAME or node_name == "kinetica:smart_chute") and math.abs(fan_dir.y) > 0 then
        return true, nil
    end

    if core.get_item_group(node_name, "lava") > 0 or string.find(node_name, "lava") then
        return true, "blasting"
    end
    if string.find(node_name, "soul_fire") or string.find(node_name, "soul_campfire") then
        return true, "haunting"
    end
    if core.get_item_group(node_name, "fire") > 0 or
       string.find(node_name, ":fire") or
       string.find(node_name, "campfire") then
        return true, "smoking"
    end
    if core.get_item_group(node_name, "water") > 0 or string.find(node_name, "water") then
        return true, "washing"
    end
    if string.find(node_name, "powder_snow") or
       node_name == "mcl_core:ice" or
       node_name == "mcl_core:packed_ice" or
       node_name == "mcl_core:blue_ice" then
        return true, "freezing"
    end

    if string.find(node_name, "iron_bars") or
       string.find(node_name, "fence") or
       string.find(node_name, "chain") or
       string.find(node_name, "trapdoor") or
       core.get_item_group(node_name, "leaves") > 0 then
        return true, nil
    end

    local def = core.registered_nodes[node_name]
    if def and def.walkable == false then
        return true, nil
    end
    return false, nil
end

local WASHING_CHANCE_RECIPES = {
    ["mcl_core:gravel"] = {
        {item = "mcl_core:flint",          chance = 0.25,  rolls = 1, count = 1},
        {item = "mcl_core:iron_nugget",    chance = 0.125, rolls = 1, count = 1},
    },
    ["mcl_core:sand"] = {
        {item = "mcl_core:clay_lump",      chance = 0.25,  rolls = 1, count = 1},
    },
    ["mcl_core:redsand"] = {
        {item = "mcl_core:gold_nugget",    chance = 0.125, rolls = 3, count = 1},
        {item = "mcl_core:deadbush",       chance = 0.05,  rolls = 1, count = 1},
    },
    ["mcl_nether:soul_sand"] = {
        {item = "mcl_nether:quartz",       chance = 0.125, rolls = 4, count = 1},
        {item = "mcl_core:gold_nugget",    chance = 0.02,  rolls = 1, count = 1},
    },
    ["mcl_raw_ores:raw_iron"] = {
        {item = "mcl_core:iron_nugget",    chance = 1.00,  rolls = 1, count = 9},
        {item = "mcl_redstone:redstone",   chance = 0.75,  rolls = 1, count = 1},
    },
    ["mcl_raw_ores:raw_gold"] = {
        {item = "mcl_core:gold_nugget",    chance = 1.00,  rolls = 1, count = 9},
        {item = "mcl_nether:quartz",       chance = 0.50,  rolls = 1, count = 1},
    },
    ["mcl_copper:raw_copper"] = {
        {item = "mcl_copper:copper_ingot", chance = 1.00,  rolls = 1, count = 1},
        {item = "mcl_core:clay_lump",      chance = 0.50,  rolls = 1, count = 1},
    },
}

local WASHING_DIRECT_RECIPES = {
    ["mcl_core:ice"]        = "mcl_core:packed_ice",
    ["mcl_nether:magma"]    = "mcl_core:obsidian",
    ["mcl_core:cobble"]     = "mcl_core:mossycobble",
    ["mcl_core:stonebrick"] = "mcl_core:stonebrickmossy",
    ["mcl_mud:mud"]         = "mcl_core:clay",
    ["mcl_sponges:sponge"]  = "mcl_sponges:sponge_wet",
    ["mcl_torches:torch"]   = "mcl_core:stick",
}

local HAUNTING_CHANCE_RECIPES = {
    ["mcl_core:lapis"] = {
        {item = "mcl_ocean:prismarine_shard",    chance = 0.75,  rolls = 1, count = 1},
        {item = "mcl_ocean:prismarine_crystals", chance = 0.125, rolls = 1, count = 1},
    },
}

local HAUNTING_DIRECT_RECIPES = {
    ["mcl_core:sand"]                 = "mcl_nether:soul_sand",
    ["mcl_core:redsand"]              = "mcl_nether:soul_sand",
    ["mcl_core:dirt"]                 = "mcl_blackstone:soul_soil",
    ["mcl_core:dirt_with_grass"]      = "mcl_blackstone:soul_soil",
    ["mcl_core:cobble"]               = "mcl_blackstone:blackstone",
    ["mcl_core:stone"]                = "mcl_core:cobble",
    ["mcl_core:stonebrick"]           = "mcl_core:stonebrickcracked",
    ["mcl_torches:torch"]             = "mcl_blackstone:soul_torch",
    ["mcl_lanterns:lantern_floor"]    = "mcl_lanterns:soul_lantern_floor",
    ["mcl_campfires:campfire"]        = "mcl_campfires:soul_campfire",
    ["mcl_campfires:campfire_lit"]    = "mcl_campfires:soul_campfire_lit",
    ["mcl_farming:bread"]             = "mcl_farming:potato_item_poison",
    ["mcl_sweet_berry:sweet_berries"] = "mcl_lush_caves:glow_berry",
    ["mcl_Farming:sweet_berry"]       = "mcl_lush_caves:glow_berry",
    ["mcl_mushrooms:mushroom_brown"]  = "mcl_crimson:crimson_fungus",
    ["mcl_mushrooms:mushroom_red"]    = "mcl_crimson:warped_fungus",
    ["mcl_nether:netherbrick"]        = "mcl_nether:red_nether_brick_block",
    ["mcl_ocean:prismarine"]          = "mcl_ocean:prismarine_dark",
    ["mcl_core:coal_lump"]            = "mcl_nether:glowstone_dust",
}

local FREEZING_RECIPES = {
    ["mcl_buckets:bucket_water"]       = "mcl_core:ice",
    ["mcl_buckets:bucket_river_water"] = "mcl_core:ice",
    ["mcl_buckets:bucket_lava"]        = "mcl_core:obsidian",
    ["mcl_core:ice"]                   = "mcl_core:packed_ice",
    ["mcl_core:packed_ice"]            = "mcl_core:blue_ice",
    ["mcl_mobitems:magma_cream"]       = "mcl_mobitems:slimeball",
    ["mcl_potions:water"]              = "mcl_throwing:snowball",
}

local function is_food_item(itemname)
    local def = core.registered_items[itemname]
    if not def then return false end
    if def.groups and (def.groups.food or def.groups.eatable) then
        return true
    end
    if string.find(itemname, "beef") or
       string.find(itemname, "pork") or
       string.find(itemname, "chicken") or
       string.find(itemname, "mutton") or
       string.find(itemname, "rabbit") or
       string.find(itemname, "cod") or
       string.find(itemname, "salmon") or
       string.find(itemname, "potato") or
       string.find(itemname, "kelp") or
       string.find(itemname, "bread") or
       string.find(itemname, "cooked") then
        return true
    end
    return false
end

local function get_special_washed_item(itemname)
    local direct = WASHING_DIRECT_RECIPES[itemname]
    if direct and core.registered_items[direct] then
        return direct
    end
    if string.find(itemname, "concrete_powder") then
        local hardened = string.gsub(itemname, "_powder", "")
        if core.registered_items[hardened] then
            return hardened
        end
    end
    if string.sub(itemname, 1, 9) == "mcl_wool:" and itemname ~= "mcl_wool:white" then
        if not string.find(itemname, "carpet") and core.registered_items["mcl_wool:white"] then
            return "mcl_wool:white"
        elseif string.find(itemname, "carpet") and core.registered_items["mcl_wool:white_carpet"] then
            return "mcl_wool:white_carpet"
        end
    end
    if string.sub(itemname, 1, 15) == "mcl_core:glass_" and core.registered_items["mcl_core:glass"] then
        return "mcl_core:glass"
    end
    if string.sub(itemname, 1, 12) == "xpanes:pane_" and core.registered_items["xpanes:bar_flat"] then
        return "xpanes:bar_flat"
    end
    return nil
end

local function get_stream_particle_style(catalyst)
    if catalyst == "blasting" then
        return "bubble.png^[colorize:#ff3b00:235", "bubble.png^[colorize:#ffb300:220", 1.4, 2.4, 14
    elseif catalyst == "smoking" then
        return "bubble.png^[colorize:#262626:230", "bubble.png^[colorize:#707070:200", 1.6, 2.8, 0
    elseif catalyst == "haunting" then
        return "bubble.png^[colorize:#00f0ff:230", "bubble.png^[colorize:#008090:215", 1.4, 2.4, 13
    elseif catalyst == "washing" then
        return "bubble.png^[colorize:#1ca3ec:215", "bubble.png^[colorize:#8be0ff:200", 1.3, 2.2, 0
    elseif catalyst == "freezing" then
        return "bubble.png^[colorize:#b0f4ff:230", "bubble.png^[colorize:#ffffff:230", 1.2, 2.1, 6
    end
    return "bubble.png^[colorize:#ffffff:155", nil, 1.1, 1.9, 0
end

local function spawn_item_processing_particles(opos, catalyst)
    local tex1, tex2, _, _, glow = get_stream_particle_style(catalyst)

    core.add_particlespawner({
        amount = 4,
        time = CONFIG.TICK_INTERVAL,
        minpos = {x = opos.x - 0.18, y = opos.y - 0.1, z = opos.z - 0.18},
        maxpos = {x = opos.x + 0.18, y = opos.y + 0.2, z = opos.z + 0.18},
        minvel = {x = -0.25, y = 0.45, z = -0.25},
        maxvel = {x =  0.25, y = 0.95, z =  0.25},
        minexptime = 0.2,
        maxexptime = 0.45,
        minsize = 1.1,
        maxsize = 1.9,
        collisiondetection = false,
        glow = glow,
        texture = tex2 or tex1,
    })
end

local function execute_chance_table_drops(opos, count, chance_table)
    local out_totals = {}
    for _ = 1, count do
        for _, rule in ipairs(chance_table) do
            if core.registered_items[rule.item] then
                local rolls = rule.rolls or 1
                local qty   = rule.count or 1
                for _ = 1, rolls do
                    if math.random() <= rule.chance then
                        out_totals[rule.item] = (out_totals[rule.item] or 0) + qty
                    end
                end
            end
        end
    end

    for item_name, total_qty in pairs(out_totals) do
        local max_s = ItemStack(item_name):get_stack_max()
        while total_qty > 0 do
            local batch = math.min(total_qty, max_s)
            core.add_item(opos, ItemStack(item_name .. " " .. batch))
            total_qty = total_qty - batch
        end
    end
end

local function process_item_entity(obj, luaent, catalyst, rpm)
    if not CONFIG.ENABLE_BULK_PROCESS or not catalyst then
        return
    end

    local stack = ItemStack(luaent.itemstring or "")
    if stack:is_empty() then return end

    local itemname = stack:get_name()
    local count    = stack:get_count()
    local opos     = obj:get_pos()
    if not opos then return end

    local can_process = false
    local cooked_res  = nil

    if catalyst == "washing" then
        if WASHING_CHANCE_RECIPES[itemname] or get_special_washed_item(itemname) then
            can_process = true
        end
    elseif catalyst == "haunting" then
        local out = HAUNTING_DIRECT_RECIPES[itemname]
        if HAUNTING_CHANCE_RECIPES[itemname] or (out and core.registered_items[out]) then
            can_process = true
        end
    elseif catalyst == "freezing" then
        local out = FREEZING_RECIPES[itemname]
        if out and core.registered_items[out] then
            can_process = true
        end
    elseif catalyst == "smoking" or catalyst == "blasting" then
        cooked_res = core.get_craft_result({
            method = "cooking",
            width = 1,
            items = {ItemStack(itemname)},
        })
        if cooked_res and cooked_res.item and not cooked_res.item:is_empty() then
            local out_name = cooked_res.item:get_name()
            if catalyst == "smoking" then
                if is_food_item(itemname) or is_food_item(out_name) then
                    can_process = true
                end
            else
                can_process = true
            end
        end
    end

    if not can_process then
        return
    end

    spawn_item_processing_particles(opos, catalyst)

    if luaent._kinetica_catalyst ~= catalyst then
        luaent._kinetica_catalyst = catalyst
        luaent._kinetica_proc_timer = 0
    end

    local req_time = get_process_time(rpm, count)
    luaent._kinetica_proc_timer = (luaent._kinetica_proc_timer or 0) + CONFIG.TICK_INTERVAL
    if luaent._kinetica_proc_timer < req_time then
        return
    end
    luaent._kinetica_proc_timer = 0

    if catalyst == "washing" then
        local direct = get_special_washed_item(itemname)
        if direct then
            luaent.itemstring = ItemStack(direct .. " " .. count):to_string()
            return
        end
        local drops = WASHING_CHANCE_RECIPES[itemname]
        if drops then
            execute_chance_table_drops(opos, count, drops)
            luaent.itemstring = ""
            obj:remove()
        end
        return
    end

    if catalyst == "haunting" then
        local drops = HAUNTING_CHANCE_RECIPES[itemname]
        if drops then
            execute_chance_table_drops(opos, count, drops)
            luaent.itemstring = ""
            obj:remove()
            return
        end
        local out_name = HAUNTING_DIRECT_RECIPES[itemname]
        if out_name and core.registered_items[out_name] then
            luaent.itemstring = ItemStack(out_name .. " " .. count):to_string()
        end
        return
    end

    if catalyst == "freezing" then
        local out_name = FREEZING_RECIPES[itemname]
        if out_name and core.registered_items[out_name] then
            luaent.itemstring = ItemStack(out_name .. " " .. count):to_string()
            if string.find(itemname, "bucket_") and core.registered_items["mcl_buckets:bucket_empty"] then
                core.add_item(opos, ItemStack("mcl_buckets:bucket_empty " .. count))
            end
        end
        return
    end

    if (catalyst == "smoking" or catalyst == "blasting") and cooked_res and cooked_res.item then
        local out_name  = cooked_res.item:get_name()
        local total_out = cooked_res.item:get_count() * count
        luaent.itemstring = ItemStack(out_name .. " " .. total_out):to_string()
    end
end

local function spawn_stream_segment_particles(pos, fan_dir, is_pull, start_dist, end_dist, catalyst, p_speed)
    local origin_d = start_dist - 0.45
    local target_d = end_dist + 0.15
    local seg_len  = target_d - origin_d
    if seg_len <= 0.1 then return end

    local effective_cat = (not is_pull) and catalyst or nil
    local tex1, tex2, min_sz, max_sz, glow = get_stream_particle_style(effective_cat)
    local travel_time = seg_len / math.max(0.5, p_speed)
    local wind_sign   = is_pull and -1 or 1
    local vx          = fan_dir.x * p_speed * wind_sign
    local vy          = fan_dir.y * p_speed * wind_sign
    local vz          = fan_dir.z * p_speed * wind_sign

    local spawn_d = is_pull and target_d or origin_d
    local spawn_pt = {
        x = pos.x + fan_dir.x * spawn_d,
        y = pos.y + fan_dir.y * spawn_d,
        z = pos.z + fan_dir.z * spawn_d,
    }

    local amount = math.max(3, math.min(16, math.ceil(seg_len * 1.4)))

    core.add_particlespawner({
        amount = amount,
        time = CONFIG.TICK_INTERVAL,
        minpos = {x = spawn_pt.x - 0.22, y = spawn_pt.y - 0.22, z = spawn_pt.z - 0.22},
        maxpos = {x = spawn_pt.x + 0.22, y = spawn_pt.y + 0.22, z = spawn_pt.z + 0.22},
        minvel = {x = vx, y = vy, z = vz},
        maxvel = {x = vx, y = vy, z = vz},
        minexptime = travel_time * 0.96,
        maxexptime = travel_time * 1.02,
        minsize = min_sz,
        maxsize = max_sz,
        collisiondetection = false,
        glow = glow,
        texture = tex1,
    })

    if tex2 then
        core.add_particlespawner({
            amount = math.max(2, math.floor(amount * 0.6)),
            time = CONFIG.TICK_INTERVAL,
            minpos = {x = spawn_pt.x - 0.20, y = spawn_pt.y - 0.20, z = spawn_pt.z - 0.20},
            maxpos = {x = spawn_pt.x + 0.20, y = spawn_pt.y + 0.20, z = spawn_pt.z + 0.20},
            minvel = {x = vx, y = vy, z = vz},
            maxvel = {x = vx, y = vy, z = vz},
            minexptime = travel_time * 0.95,
            maxexptime = travel_time * 1.02,
            minsize = min_sz * 0.85,
            maxsize = max_sz * 0.90,
            collisiondetection = false,
            glow = glow,
            texture = tex2,
        })
    end
end

local function brake_items_in_corridor(pos, fan_dir, max_dist)
    for dist = 1, max_dist do
        local cpos = {
            x = pos.x + fan_dir.x * dist,
            y = pos.y + fan_dir.y * dist,
            z = pos.z + fan_dir.z * dist,
        }
        local objs = core.get_objects_inside_radius(cpos, 0.9)
        for _, obj in ipairs(objs) do
            local luaent = obj:get_luaentity()
            if luaent and luaent.name == "__builtin:item" and luaent._kinetica_fan_pushed then
                luaent._kinetica_fan_pushed = false
                local vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
                obj:set_velocity({x = 0, y = (fan_dir.y ~= 0) and 0 or vel.y, z = 0})
            end
        end
    end
end

local function apply_fan_airflow(pos, meta, fan_dir, wind_dir, is_pull, rpm)
    local max_range      = get_airflow_range(rpm)
    local item_speed     = get_item_speed(rpm)
    local entity_speed   = get_entity_speed(rpm)
    local particle_speed = get_particle_speed(rpm)

    local active_catalyst = nil
    local first_cat_dist  = nil
    local actual_reach    = 0
    local cell_catalysts  = {}

    for dist = 1, max_range do
        local cpos = {
            x = pos.x + fan_dir.x * dist,
            y = pos.y + fan_dir.y * dist,
            z = pos.z + fan_dir.z * dist,
        }
        local cnode = core.get_node(cpos)
        local passable, cat = classify_stream_node(cnode.name, fan_dir)

        if not passable then
            break
        end

        actual_reach = dist

        if not is_pull and cat then
            if not active_catalyst or (CATALYST_PRIORITY[cat] or 0) >= (CATALYST_PRIORITY[active_catalyst] or 0) then
                active_catalyst = cat
            end
            if not first_cat_dist then
                first_cat_dist = dist
            end
        end

        cell_catalysts[dist] = (not is_pull) and active_catalyst or nil

        if cnode.name == CHUTE_NAME or cnode.name == "kinetica:smart_chute" or cnode.name == DEPOT_NAME then
            local ct = core.get_node_timer(vector.new(cpos.x, cpos.y, cpos.z))
            if ct and not ct:is_started() then
                ct:start(0.20)
            end
        end
    end

    if actual_reach == 0 then
        return 0, nil
    end

    local max_push_proj = actual_reach + 0.05
    local min_pull_proj = 0.85

    local do_damage_tick = false
    local dmg_acc = meta:get_float("cat_dmg_timer") + CONFIG.TICK_INTERVAL
    if dmg_acc >= CONFIG.CATALYST_DAMAGE_INTERVAL then
        meta:set_float("cat_dmg_timer", 0)
        do_damage_tick = true
    else
        meta:set_float("cat_dmg_timer", dmg_acc)
    end

    local seen_objs = {}
    for dist = 1, actual_reach + 1 do
        local cpos = {
            x = pos.x + fan_dir.x * dist,
            y = pos.y + fan_dir.y * dist,
            z = pos.z + fan_dir.z * dist,
        }
        local cell_idx   = math.min(dist, actual_reach)
        local stream_cat = cell_catalysts[cell_idx]

        local objs = core.get_objects_inside_radius(cpos, 0.85)
        for _, obj in ipairs(objs) do
            if not seen_objs[obj] then
                seen_objs[obj] = true
                local luaent = obj:get_luaentity()
                local opos   = obj:get_pos()

                if opos then
                    local rel_x = opos.x - pos.x
                    local rel_y = opos.y - pos.y
                    local rel_z = opos.z - pos.z
                    local proj  = rel_x * fan_dir.x + rel_y * fan_dir.y + rel_z * fan_dir.z

                    local lat_x = math.abs(rel_x - proj * fan_dir.x)
                    local lat_y = math.abs(rel_y - proj * fan_dir.y)
                    local lat_z = math.abs(rel_z - proj * fan_dir.z)
                    local in_tunnel = (lat_x <= 0.65 and lat_y <= 0.75 and lat_z <= 0.65)

                    if luaent and luaent.name == "__builtin:item" and in_tunnel then
                        if not is_pull then
                            if proj >= 0.35 and proj < max_push_proj then
                                luaent._kinetica_fan_pushed = true
                                if math.abs(fan_dir.y) > 0 then
                                    local cx = pos.x + (opos.x - pos.x) * 0.35
                                    local cz = pos.z + (opos.z - pos.z) * 0.35
                                    obj:set_pos({x = cx, y = opos.y, z = cz})
                                end
                                local rem_dist = max_push_proj - proj
                                local max_step_speed = rem_dist / CONFIG.TICK_INTERVAL
                                local eff_speed = math.min(item_speed, max_step_speed)

                                obj:set_velocity({
                                    x = wind_dir.x * eff_speed,
                                    y = (wind_dir.y ~= 0) and (wind_dir.y * eff_speed) or 0,
                                    z = wind_dir.z * eff_speed,
                                })
                            elseif proj >= max_push_proj and proj <= (actual_reach + 1.5) then
                                luaent._kinetica_fan_pushed = false
                                local vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
                                obj:set_velocity({
                                    x = 0,
                                    y = (fan_dir.y ~= 0) and 0 or vel.y,
                                    z = 0,
                                })
                            end

                            if stream_cat and proj >= 0.35 and proj <= (actual_reach + 0.5) then
                                process_item_entity(obj, luaent, stream_cat, rpm)
                            end
                        else
                            if proj > min_pull_proj and proj <= (actual_reach + 0.25) then
                                luaent._kinetica_fan_pushed = true
                                local rem_dist = proj - min_pull_proj
                                local max_step_speed = rem_dist / CONFIG.TICK_INTERVAL
                                local eff_speed = math.min(item_speed, max_step_speed)

                                obj:set_velocity({
                                    x = wind_dir.x * eff_speed,
                                    y = (wind_dir.y ~= 0) and (wind_dir.y * eff_speed) or 0,
                                    z = wind_dir.z * eff_speed,
                                })
                            elseif proj <= min_pull_proj and proj >= 0.35 then
                                luaent._kinetica_fan_pushed = false
                                local vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
                                obj:set_velocity({
                                    x = 0,
                                    y = (fan_dir.y ~= 0) and 0 or vel.y,
                                    z = 0,
                                })
                            end
                        end

                    elseif CONFIG.PUSH_PLAYERS_AND_MOBS and in_tunnel and proj >= 0.35 and proj <= (actual_reach + 0.2) and
                           (obj:is_player() or (luaent and (luaent.is_mob or luaent._cmi_is_mob or luaent.health))) then
                        if obj:is_player() then
                            obj:add_velocity({
                                x = wind_dir.x * entity_speed * CONFIG.TICK_INTERVAL * 4,
                                y = (wind_dir.y > 0) and (wind_dir.y * entity_speed * CONFIG.TICK_INTERVAL * 5) or 0,
                                z = wind_dir.z * entity_speed * CONFIG.TICK_INTERVAL * 4,
                            })
                        else
                            local vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
                            obj:set_velocity({
                                x = wind_dir.x * entity_speed,
                                y = (wind_dir.y > 0) and (wind_dir.y * entity_speed) or vel.y,
                                z = wind_dir.z * entity_speed,
                            })
                        end

                        if not is_pull and stream_cat == "washing" and mcl_burning and mcl_burning.extinguish then
                            pcall(mcl_burning.extinguish, obj)
                        elseif not is_pull and do_damage_tick and (stream_cat == "blasting" or stream_cat == "smoking" or stream_cat == "haunting") then
                            local hp_dmg = (stream_cat == "blasting") and 4 or 2
                            obj:punch(obj, 1.0, {
                                full_punch_interval = 1.0,
                                damage_groups = {fleshy = hp_dmg},
                            }, nil)
                            if (stream_cat == "blasting" or stream_cat == "smoking") and mcl_burning and mcl_burning.set_on_fire then
                                pcall(mcl_burning.set_on_fire, obj, 3)
                            end
                        end
                    end
                end
            end
        end
    end

    if not is_pull and first_cat_dist then
        if first_cat_dist > 1 then
            spawn_stream_segment_particles(pos, fan_dir, false, 1, first_cat_dist - 1, nil, particle_speed)
        end
        spawn_stream_segment_particles(pos, fan_dir, false, first_cat_dist, actual_reach, active_catalyst, particle_speed)
    else
        spawn_stream_segment_particles(pos, fan_dir, is_pull, 1, actual_reach, nil, particle_speed)
    end

    return actual_reach, active_catalyst
end

local function compute_wind_dir(meta, fan_dir, spin_dir)
    local is_pull = false
    if CONFIG.CW_ROTATION_PUSHES then
        is_pull = (spin_dir == -1)
    else
        is_pull = (spin_dir == 1)
    end

    if meta:get_int("invert_dir") == 1 then
        is_pull = not is_pull
    end

    if is_pull then
        return {x = -fan_dir.x, y = -fan_dir.y, z = -fan_dir.z}, true, "PULL (Suction)"
    end
    return {x = fan_dir.x, y = fan_dir.y, z = fan_dir.z}, false, "PUSH (Blowing)"
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local function format_fan_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_fan_demand_ku(rpm) end
    local spin_dir  = meta:get_int("spin_dir")
    local now       = math.floor(core.get_gametime())
    local is_active = (node.name ~= IDLE_NAME) and (supply_ku > 0 and rpm >= CONFIG.MIN_RPM and now < meta:get_int("lit_until"))
    local low_rpm   = (supply_ku > 0 and rpm > 0 and rpm < CONFIG.MIN_RPM and now < meta:get_int("lit_until"))

    local fan_dir  = get_fan_dir(node.param2)
    local _, _, mode_lbl = compute_wind_dir(meta, fan_dir, spin_dir ~= 0 and spin_dir or 1)
    local reach    = is_active and meta:get_int("last_reach") or 0
    local cat_str  = is_active and meta:get_string("last_catalyst") or ""

    local state_str = "IDLE"
    if is_active then
        state_str = "ACTIVE — " .. mode_lbl
    elseif low_rpm then
        state_str = string.format("TOO SLOW (Needs >= %d RPM)", CONFIG.MIN_RPM)
    end

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Machine:  Encased Fan",
        "State:    " .. state_str,
        string.format("Speed:    %.1f RPM (Min %d RPM)", rpm, CONFIG.MIN_RPM),
        string.format("Stress:   -%d KU Load (%d / %d KU Avail)", is_active and demand_ku or 0, avail_ku, supply_ku),
        string.format("Airflow:  %d Blocks Reach (%s)", reach, string.upper(dir_to_name(fan_dir))),
        "Catalyst: " .. ((cat_str ~= "") and string.upper(cat_str) or "None (Clean Air)"),
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME] = format_fan_glasses_info

if not kinetica.get_glasses_info then
    function kinetica.get_glasses_info(pos, node)
        node = node or core.get_node(pos)
        for prefix, fn in pairs(kinetica._glasses_formatters) do
            if node.name == prefix or string.sub(node.name or "", 1, #prefix + 1) == (prefix .. "_") then
                return fn(pos, node)
            end
        end
        return core.get_meta(pos):get_string("glasses_info")
    end
end

local function set_fan_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    meta:set_string("active", "false")
    meta:set_string("airflow_dir", "none")
    meta:set_int("is_pull", 0)
    meta:set_int("last_reach", 0)
    meta:set_string("last_catalyst", "")
    meta:set_float("sfx_timer", 0)

    local fan_dir = get_fan_dir(node.param2)
    brake_items_in_corridor(pos, fan_dir, CONFIG.RANGE_AT_512_RPM + 1)

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", reason_text or string.format(
            "Encased Fan: Idle (Min %d RPM | Connect Shaft to Back | Right-Click to flip Push/Pull)",
            CONFIG.MIN_RPM
        ))
    end

    if node.name ~= IDLE_NAME then
        core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
    end
    meta:set_string("glasses_info", format_fan_glasses_info(pos, core.get_node(pos)))
end

local function wake_fan(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    if rpm < CONFIG.MIN_RPM then
        set_fan_idle(pos, node, string.format(
            "Encased Fan: Too Slow (%.0f RPM / Min %d RPM required!)",
            rpm, CONFIG.MIN_RPM
        ))
        return
    end

    local target_node = get_active_fan_node_name(rpm, spin_dir)
    if node.name ~= target_node then
        core.swap_node(pos, {name = target_node, param2 = node.param2})
    end

    local meta = core.get_meta(pos)
    local fan_dir = get_fan_dir(node.param2)
    local wind_dir, is_pull, _ = compute_wind_dir(meta, fan_dir, spin_dir)
    meta:set_string("active", "true")
    meta:set_string("airflow_dir", dir_to_name(wind_dir))
    meta:set_int("is_pull", is_pull and 1 or 0)

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(CONFIG.TICK_INTERVAL)
    end
end

local function fan_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if now >= meta:get_int("lit_until") and kinetica.update_network then
        kinetica.update_network(pos)
        node = core.get_node(pos)
    end

    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_fan_demand_ku(rpm) end
    local spin_dir  = meta:get_int("spin_dir")

    if supply_ku <= 0 or rpm < CONFIG.MIN_RPM or now >= meta:get_int("lit_until") then
        set_fan_idle(pos, node)
        return false
    end

    local target_active = get_active_fan_node_name(rpm, spin_dir)
    if node.name ~= target_active then
        core.swap_node(pos, {name = target_active, param2 = node.param2})
        node.name = target_active
    end

    -- Play sound ONLY while the fan is actively spinning
    play_fan_active_sound(pos, meta, rpm, CONFIG.TICK_INTERVAL)

    local fan_dir = get_fan_dir(node.param2)
    local wind_dir, is_pull, mode_lbl = compute_wind_dir(meta, fan_dir, spin_dir)

    meta:set_string("active", "true")
    meta:set_string("airflow_dir", dir_to_name(wind_dir))
    meta:set_int("is_pull", is_pull and 1 or 0)

    local reach, catalyst = apply_fan_airflow(pos, meta, fan_dir, wind_dir, is_pull, rpm)
    meta:set_int("last_reach", reach)
    meta:set_string("last_catalyst", (not is_pull and catalyst) or "")

    local cat_lbl = (not is_pull and catalyst) and (" | " .. string.upper(catalyst)) or ""
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", string.format(
            "Encased Fan: %s %d blk%s (-%d KU used | %d KU avail / %d KU total | %.0f RPM)",
            mode_lbl, reach, cat_lbl, demand_ku, avail_ku, supply_ku, rpm
        ))
    end

    meta:set_string("glasses_info", format_fan_glasses_info(pos, node))
    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    return false
end

local function fan_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if clicker and clicker:is_player() and clicker:get_player_control().sneak then
        return itemstack
    end
    local meta = core.get_meta(pos)
    local inv_flag = (meta:get_int("invert_dir") == 1) and 0 or 1
    meta:set_int("invert_dir", inv_flag)

    local fan_dir  = get_fan_dir(node.param2)
    local spin_dir = meta:get_int("spin_dir")
    if spin_dir == 0 then spin_dir = 1 end
    local wind_dir, is_pull, mode_lbl = compute_wind_dir(meta, fan_dir, spin_dir)

    if meta:get_string("active") == "true" then
        meta:set_string("airflow_dir", dir_to_name(wind_dir))
        meta:set_int("is_pull", is_pull and 1 or 0)
    end
    meta:set_string("glasses_info", format_fan_glasses_info(pos, node))

    if clicker and clicker:is_player() then
        core.chat_send_player(
            clicker:get_player_name(),
            "[Kinetica] Encased Fan airflow polarity: " .. mode_lbl
        )
    end
    return itemstack
end

if kinetica.register_kinetic_machine then
    kinetica.register_kinetic_machine(IDLE_NAME, {
        can_ride_piston = true,
        get_demand_ku   = function(rpm, pos, node)
            return get_fan_demand_ku(rpm)
        end,
        has_axle_port   = function(node, d)
            local back_dir = get_back_dir(node.param2)
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        end,
        set_idle = set_fan_idle,
        wake     = wake_fan,
    })
end

local common_groups = {
    handy = 1,
    pickaxey = 1,
    axey = 1,
    kinetic_receiver = 1,
    kinetica_fan = 1,
    encased_fan = 1,
}

local active_groups = {
    handy = 1,
    pickaxey = 1,
    axey = 1,
    kinetic_receiver = 1,
    kinetica_fan = 1,
    encased_fan = 1,
    not_in_creative_inventory = 1,
}

local function register_fan_variant(node_name, back_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and string.format("Encased Fan (Min %d RPM | Scales with RPM | Washes, Smokes, Blasts & Haunts)", CONFIG.MIN_RPM)
            or  "Encased Fan",
        paramtype2 = "facedir",
        is_ground_content = false,
        tiles = {
            TEX_FRONT,
            back_tile,
            TEX_SIDE,
            TEX_SIDE,
            TEX_SIDE,
            TEX_SIDE,
        },
        on_place = is_base and place_encased_fan or nil,
        on_rightclick = fan_on_rightclick,
        drop = is_base and nil or IDLE_NAME,
        groups = is_base and common_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_wood_defaults(),

        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("invert_dir", 0)
            meta:set_float("sfx_timer", 0)
            set_fan_idle(pos, core.get_node(pos))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = function(pos, oldnode)
            if oldnode then
                brake_items_in_corridor(pos, get_fan_dir(oldnode.param2), CONFIG.RANGE_AT_512_RPM + 1)
            end
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,

        on_timer = fan_timer,
    })
end

register_fan_variant(IDLE_NAME, back_idle, true)

local med_cw  = make_fan_back_anim(false, 0.24)
local med_ccw = make_fan_back_anim(true,  0.24)
register_fan_variant(ACT_CW,  med_ccw, false)
register_fan_variant(ACT_CCW, med_cw,  false)

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local b_cw  = make_fan_back_anim(false, tier.length)
    local b_ccw = make_fan_back_anim(true,  tier.length)

    register_fan_variant(IDLE_NAME .. "_" .. tier.name .. "_cw",  b_ccw, false)
    register_fan_variant(IDLE_NAME .. "_" .. tier.name .. "_ccw", b_cw,  false)
end

core.register_alias("kinetica:encased_fan_active", ACT_CW)

core.register_lbm({
    label             = "Wake kinetica Encased Fans on chunk load",
    name              = "kinetica:wake_fans_lbm",
    nodenames         = {"group:encased_fan"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TICK_INTERVAL)
        end
    end,
})

core.register_craft({
    output = "kinetica:encased_fan",
    recipe = {
        {"",                        "kinetica:sheet_iron",      ""},
        {"kinetica:andesite_alloy", "kinetica:andesite_casing", "kinetica:andesite_alloy"},
        {"",                        "kinetica:shaft",           ""},
    },
})
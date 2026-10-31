kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- SOUND CUSTOMIZATION (Plays ONLY when Water Pump is actively running)
-- ============================================================================
local SOUND_CONFIG = {
    ENABLE_SOUND            = true,
    SOUND_NAME              = "water_pump",         -- Custom .ogg in sounds/ folder (without .ogg)
    SOUND_FALLBACK          = "default_water_footstep", -- Built-in fallback sound if custom .ogg is missing
    SOUND_GAIN              = 0.25,                     -- Volume (0.0 to 1.0)
    SOUND_PITCH             = 0.85,                     -- Base pitch when SCALE_PITCH_WITH_RPM = false
    SCALE_PITCH_WITH_RPM    = true,                     -- Scale pitch dynamically with shaft RPM
    MIN_PITCH               = 0.75,                     -- Pitch at MIN_PUMP_RPM (4 RPM)
    MAX_PITCH               = 1.35,                     -- Pitch at 512+ RPM
    SOUND_INTERVAL          = 0.0,                     -- Seconds between sound triggers while active
    MAX_HEAR_DISTANCE       = 12,                       -- Max distance (blocks) players can hear it
    SOUND_ONLY_WHEN_PUMPING = false,                    -- true = only play when water is below; false = play whenever spinning
}

local CONFIG = {
    MIN_PUMP_RPM                  = kinetica.PUMP_MIN_RPM or 4,
    MAX_PUMP_CHAIN                = kinetica.MAX_PUMP_CHAIN or 5,
    MIN_WATER_PER_SEC             = 20,
    MAX_WATER_PER_SEC             = 100,
    MAX_RPM_CAP                   = 3072,
    DIRECT_FEED_STEAM_GENERATOR   = true,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
        { name = "ultra",  max_rpm = 3072, length = 0.03 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_TOP                       = "kinetica_pump_top.png",
    TEX_SIDE                      = "kinetica_pump_side.png",
    TEX_FRONT_OFF                 = "kinetica_pump_front_off.png",
    TEX_FRONT_ON                  = "kinetica_pump_front_on.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME       = "kinetica:water_pump"
local ACTIVE_CW_NAME  = "kinetica:water_pump_active_cw"
local ACTIVE_CCW_NAME = "kinetica:water_pump_active_ccw"

local MIN_PUMP_RPM   = CONFIG.MIN_PUMP_RPM
local MAX_PUMP_CHAIN = CONFIG.MAX_PUMP_CHAIN

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

local function play_pump_active_sound(pos, meta, rpm, found_water, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not RESOLVED_SOUND or RESOLVED_SOUND == "" then
        return
    end
    if SOUND_CONFIG.SOUND_ONLY_WHEN_PUMPING and not found_water then
        return
    end

    local acc = meta:get_float("sfx_timer") + (dt or 1.0)
    if acc < (SOUND_CONFIG.SOUND_INTERVAL or 1.0) then
        meta:set_float("sfx_timer", acc)
        return
    end
    meta:set_float("sfx_timer", 0)

    local pitch = SOUND_CONFIG.SOUND_PITCH or 0.85
    if SOUND_CONFIG.SCALE_PITCH_WITH_RPM then
        local t = math.min(1.0, math.max(0.0, ((rpm or MIN_PUMP_RPM) - MIN_PUMP_RPM) / (512 - MIN_PUMP_RPM)))
        local min_p = SOUND_CONFIG.MIN_PITCH or 0.75
        local max_p = SOUND_CONFIG.MAX_PITCH or 1.35
        pitch = min_p + t * (max_p - min_p)
    end

    core.sound_play(RESOLVED_SOUND, {
        pos               = pos,
        gain              = SOUND_CONFIG.SOUND_GAIN or 0.25,
        pitch             = pitch,
        max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 12,
    }, true)
end

local function is_water_pump_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_water_pump = is_water_pump_node

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_active_pump_node_name(rpm, vis_spin)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (vis_spin == 1) and "cw" or "ccw"
    local candidate = IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then
        return candidate
    end
    return (vis_spin == 1) and ACTIVE_CW_NAME or ACTIVE_CCW_NAME
end

local function is_water_source_or_flowing(name)
    return name == "mcl_core:water_source" or
           name == "mcl_core:water_flowing" or
           name == "mclx_core:river_water_source" or
           name == "mclx_core:river_water_flowing" or
           core.get_item_group(name, "water") > 0
end

local function get_pump_axle_dirs(param2)
    local back_dir  = core.facedir_to_dir((param2 or 0) % 4) or {x = 0, y = 0, z = 1}
    local right_dir = {x = back_dir.z, y = 0, z = -back_dir.x}
    local left_dir  = {x = -right_dir.x, y = 0, z = -right_dir.z}
    return {right_dir, left_dir}
end

local function get_pump_chain_size(pos, right_dir)
    local left_dir = {x = -right_dir.x, y = 0, z = -right_dir.z}
    local count = 1

    for i = 1, 6 do
        local p = {x = pos.x + right_dir.x * i, y = pos.y, z = pos.z + right_dir.z * i}
        if kinetica.is_water_pump(core.get_node(p).name) then
            count = count + 1
        else
            break
        end
    end
    for i = 1, 6 do
        local p = {x = pos.x + left_dir.x * i, y = pos.y, z = pos.z + left_dir.z * i}
        if kinetica.is_water_pump(core.get_node(p).name) then
            count = count + 1
        else
            break
        end
    end
    return count
end

local function calc_pump_water_rate(rpm)
    if not rpm or rpm < MIN_PUMP_RPM then return 0 end
    if kinetica.get_pump_water_rate then
        return kinetica.get_pump_water_rate(rpm)
    end
    return math.min(
        CONFIG.MAX_WATER_PER_SEC,
        math.max(CONFIG.MIN_WATER_PER_SEC, 19 + math.floor((rpm / 512) * 81))
    )
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local function format_water_pump_glasses_info(pos, node)
    local meta       = core.get_meta(pos)
    local now        = math.floor(core.get_gametime())
    local rpm        = meta:get_float("rpm")
    local supply_ku  = meta:get_int("network_supply_ku")
    local avail_ku   = meta:get_int("rotational_power")
    local demand_ku  = meta:get_int("pump_demand_ku")
    if demand_ku <= 0 then
        demand_ku = kinetica.get_pump_demand_ku and kinetica.get_pump_demand_ku(rpm) or 20
    end
    local is_powered = (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))
    local is_active  = is_powered and (rpm >= MIN_PUMP_RPM) and (meta:get_int("pump_overloaded") == 0)
    local has_water  = (meta:get_int("has_water_below") == 1)
    local pump_rate  = is_active and (has_water and meta:get_int("pump_rate") or 0) or 0
    local chain_sz   = math.max(1, meta:get_int("chain_size"))

    local state_str = "IDLE"
    if meta:get_int("pump_overloaded") == 1 then
        state_str = string.format("OVERLOADED (Max %d Pumps in Chain!)", MAX_PUMP_CHAIN)
    elseif is_powered and rpm < MIN_PUMP_RPM then
        state_str = string.format("TOO SLOW (Min %d RPM)", MIN_PUMP_RPM)
    elseif is_active then
        state_str = has_water and "PUMPING WATER" or "RUNNING DRY (No Water Below!)"
    end

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Machine:    Mechanical Water Pump",
        "State:      " .. state_str,
        string.format("Speed:      %.1f RPM (Min %d RPM)", is_powered and rpm or 0, MIN_PUMP_RPM),
        string.format("Power:      %d / %d KU Avail (-%d KU Load)", is_powered and avail_ku or 0, supply_ku, is_active and demand_ku or 0),
        string.format("Pump Output:%d Water/s (Top Port)", pump_rate),
        string.format("Intake (-Y):%s | Chain: %d/%d", has_water and "Water Detected" or "Dry / Air", chain_sz, MAX_PUMP_CHAIN),
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME] = format_water_pump_glasses_info

local function pump_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if now >= meta:get_int("lit_until") and kinetica.update_network then
        kinetica.update_network(pos)
        node = core.get_node(pos)
    end

    local rpm        = meta:get_float("rpm")
    local supply_ku  = meta:get_int("network_supply_ku")
    local avail_ku   = meta:get_int("rotational_power")
    local demand_ku  = meta:get_int("pump_demand_ku")
    if demand_ku <= 0 then
        demand_ku = kinetica.get_pump_demand_ku and kinetica.get_pump_demand_ku(rpm) or 20
    end
    local canon_spin = meta:get_int("spin_dir")

    local bottom_pos  = {x = pos.x, y = pos.y - 1, z = pos.z}
    local found_water = is_water_source_or_flowing(core.get_node(bottom_pos).name)
    meta:set_int("has_water_below", found_water and 1 or 0)

    if supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until") then
        local axles      = get_pump_axle_dirs(node.param2)
        local chain_size = get_pump_chain_size(pos, axles[1])
        meta:set_int("chain_size", chain_size)

        if chain_size > MAX_PUMP_CHAIN then
            meta:set_int("pump_overloaded", 1)
            meta:set_int("pump_rate", 0)
            meta:set_float("sfx_timer", 0)
            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                meta:set_string("infotext", string.format("Water Pump: OVERLOADED (Max %d Pumps in a Chain!)", MAX_PUMP_CHAIN))
            end
            if node.name ~= IDLE_NAME then
                core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
                node.name = IDLE_NAME
            end
            meta:set_string("glasses_info", format_water_pump_glasses_info(pos, node))
            return true
        end
        meta:set_int("pump_overloaded", 0)

        if rpm < MIN_PUMP_RPM then
            meta:set_int("pump_rate", 0)
            meta:set_float("sfx_timer", 0)
            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                meta:set_string("infotext", string.format(
                    "Water Pump: Too Slow (%.0f RPM / Min %d RPM Required!)",
                    rpm, MIN_PUMP_RPM
                ))
            end
            if node.name ~= IDLE_NAME then
                core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
                node.name = IDLE_NAME
            end
            meta:set_string("glasses_info", format_water_pump_glasses_info(pos, node))
            return true
        end

        local right_sign  = axles[1].x + axles[1].z
        local vis_spin    = (canon_spin * right_sign >= 0) and 1 or -1
        local target_node = get_active_pump_node_name(rpm, vis_spin)
        if node.name ~= target_node then
            core.swap_node(pos, {name = target_node, param2 = node.param2})
            node.name = target_node
        end

        -- Play sound ONLY when the pump is actively running
        play_pump_active_sound(pos, meta, rpm, found_water, 1.0)

        local top_pos     = {x = pos.x, y = pos.y + 1, z = pos.z}
        local pump_amount = calc_pump_water_rate(rpm)
        meta:set_int("max_pump_rate", pump_amount)

        if found_water then
            meta:set_int("pump_rate", pump_amount)
            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                meta:set_string("infotext", string.format(
                    "Water Pump: ACTIVE (-%d KU used | %d KU avail / %d KU total | %.0f RPM) -> Pumping %d Water/s",
                    demand_ku, avail_ku, supply_ku, rpm, pump_amount
                ))
            end
            local top_node = core.get_node(top_pos)
            if kinetica.can_pipe_accept and kinetica.can_pipe_accept(top_pos, "water") then
                kinetica.add_fluid_to_pipe(top_pos, "water", pump_amount)

            elseif CONFIG.DIRECT_FEED_STEAM_GENERATOR and
                   (top_node.name == "kinetica:steam_generator" or top_node.name == "kinetica:steam_generator_active") then
                local gmeta   = core.get_meta(top_pos)
                local g_water = gmeta:get_int("water_level")
                if g_water < 100 then
                    local new_water = math.min(100, g_water + pump_amount)
                    gmeta:set_int("water_level", new_water)
                    if kinetica.get_steam_gen_formspec then
                        local ginv      = gmeta:get_inventory()
                        local show_icon = ginv and ginv:get_stack("water", 1):is_empty() or false
                        local b_time    = gmeta:get_float("burn_time")
                        local m_burn    = math.max(1, gmeta:get_float("max_burn"))
                        local b_pct     = (b_time > 0) and ((b_time / m_burn) * 100) or 0
                        gmeta:set_string("formspec", kinetica.get_steam_gen_formspec(b_pct, new_water, show_icon))
                    end
                    local gtimer = core.get_node_timer(top_pos)
                    if not gtimer:is_started() then gtimer:start(1.0) end
                end
            else
                core.add_particlespawner({
                    amount     = 8,
                    time       = 1.0,
                    minpos     = {x = pos.x - 0.12, y = pos.y + 0.52, z = pos.z - 0.12},
                    maxpos     = {x = pos.x + 0.12, y = pos.y + 0.62, z = pos.z + 0.12},
                    minvel     = {x = -0.15, y = 0.55, z = -0.15},
                    maxvel     = {x =  0.15, y = 1.15, z =  0.15},
                    minexptime = 0.45,
                    maxexptime = 0.95,
                    minsize    = 1.0,
                    maxsize    = 2.0,
                    texture    = "kinetica_pipe.png^[colorize:#2266ff:200",
                })
            end
        else
            meta:set_int("pump_rate", 0)
            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                meta:set_string("infotext", string.format(
                    "Water Pump: ACTIVE (-%d KU used | %d KU avail / %d KU total | %.0f RPM) - NO WATER BELOW!",
                    demand_ku, avail_ku, supply_ku, rpm
                ))
            end
        end

        meta:set_string("glasses_info", format_water_pump_glasses_info(pos, node))
        return true
    else
        meta:set_int("pump_rate", 0)
        meta:set_int("pump_overloaded", 0)
        meta:set_float("sfx_timer", 0)
        if kinetica.set_node_idle then
            kinetica.set_node_idle(pos, node)
        elseif node.name ~= IDLE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
        end
        meta:set_string("glasses_info", format_water_pump_glasses_info(pos, core.get_node(pos)))
        return false
    end
end

local idle_side_with_shaft = "[combine:16x16:0,0=" .. CONFIG.TEX_SIDE .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY

local function make_pump_overlay(reverse, anim_length)
    local bg      = CONFIG.TEX_SIDE
    local overlay = CONFIG.TEX_SHAFT_OVERLAY
    local tex = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg

    if reverse then
        tex = tex ..
            ":0,0=("  .. overlay .. "\\^[sheet\\:1x4\\:0,0)" ..
            ":0,16=(" .. overlay .. "\\^[sheet\\:1x4\\:0,3)" ..
            ":0,32=(" .. overlay .. "\\^[sheet\\:1x4\\:0,2)" ..
            ":0,48=(" .. overlay .. "\\^[sheet\\:1x4\\:0,1)"
    else
        tex = tex .. ":0,0=" .. overlay
    end

    return {
        name = tex,
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.24,
        },
    }
end

local function make_pump_fan_anim(reverse, anim_length)
    if kinetica.make_4frame_anim then
        return kinetica.make_4frame_anim(CONFIG.TEX_FRONT_ON, reverse, "", anim_length)
    end
    local tex = CONFIG.TEX_FRONT_ON
    if reverse then
        tex = "[combine:16x64" ..
            ":0,0=("  .. CONFIG.TEX_FRONT_ON .. "\\^[sheet\\:1x4\\:0,0)" ..
            ":0,16=(" .. CONFIG.TEX_FRONT_ON .. "\\^[sheet\\:1x4\\:0,3)" ..
            ":0,32=(" .. CONFIG.TEX_FRONT_ON .. "\\^[sheet\\:1x4\\:0,2)" ..
            ":0,48=(" .. CONFIG.TEX_FRONT_ON .. "\\^[sheet\\:1x4\\:0,1)"
    end
    return {
        name = tex,
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.24,
        },
    }
end

local base_groups   = {pickaxey = 1, kinetic_receiver = 1, steam_connectable = 1, pipe_water = 1, kinetica_water_pump = 1}
local active_groups = {pickaxey = 1, kinetic_receiver = 1, not_in_creative_inventory = 1, steam_connectable = 1, pipe_water = 1, kinetica_water_pump = 1}

local function register_pump_variant(node_name, right_tile, left_tile, back_tile, front_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and string.format("Mechanical Water Pump (Min %d RPM | Scales Water/s with RPM)", MIN_PUMP_RPM)
            or  "Mechanical Water Pump",
        tiles = {
            CONFIG.TEX_TOP,
            CONFIG.TEX_TOP,
            right_tile,
            left_tile,
            back_tile,
            front_tile,
        },
        paramtype2 = "facedir",
        drop = is_base and nil or IDLE_NAME,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_metal_defaults(),

        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("pump_rate", 0)
            meta:set_int("has_water_below", 0)
            meta:set_int("chain_size", 1)
            meta:set_float("sfx_timer", 0)
            if kinetica.set_node_idle then
                kinetica.set_node_idle(pos, core.get_node(pos))
            end
            meta:set_string("glasses_info", format_water_pump_glasses_info(pos, core.get_node(pos)))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = function(pos)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,

        on_timer = pump_timer,
    })
end

register_pump_variant(
    IDLE_NAME,
    idle_side_with_shaft,
    idle_side_with_shaft,
    CONFIG.TEX_FRONT_OFF,
    CONFIG.TEX_FRONT_OFF,
    true
)

local med_axle_cw  = make_pump_overlay(false, 0.24)
local med_axle_ccw = make_pump_overlay(true,  0.24)
local med_fan_cw   = make_pump_fan_anim(false, 0.24)
local med_fan_ccw  = make_pump_fan_anim(true,  0.24)

register_pump_variant(ACTIVE_CW_NAME,  med_axle_ccw, med_axle_cw,  med_fan_ccw, med_fan_cw,  false)
register_pump_variant(ACTIVE_CCW_NAME, med_axle_cw,  med_axle_ccw, med_fan_cw,  med_fan_ccw, false)

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local a_cw  = make_pump_overlay(false, tier.length)
    local a_ccw = make_pump_overlay(true,  tier.length)
    local f_cw  = make_pump_fan_anim(false, tier.length)
    local f_ccw = make_pump_fan_anim(true,  tier.length)

    register_pump_variant(IDLE_NAME .. "_" .. tier.name .. "_cw",  a_ccw, a_cw,  f_ccw, f_cw,  false)
    register_pump_variant(IDLE_NAME .. "_" .. tier.name .. "_ccw", a_cw,  a_ccw, f_cw,  f_ccw, false)
end

core.register_on_mods_loaded(function()
    kinetica.is_water_pump = is_water_pump_node
end)

core.register_lbm({
    label             = "Wake kinetica Water Pumps on chunk load",
    name              = "kinetica:wake_water_pumps_lbm",
    nodenames         = {"group:kinetica_water_pump"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(1.0)
        end
    end,
})

core.register_craft({
    output = "kinetica:water_pump",
    recipe = {
        {"",               "kinetica:sheet_copper",  ""},
        {"kinetica:shaft", "kinetica:copper_casing", "kinetica:shaft"},
        {"",               "kinetica:sheet_copper",  ""},
    },
})
-- kinetica/steam_turbine.lua
kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

local SOUND_CONFIG = {
    ENABLE_SOUND            = true,
    SOUND_NAME              = "Turbine_Sound",      -- Custom .ogg in sounds/ folder (without .ogg)
    SOUND_FALLBACK          = "default_dig_cracky", -- Built-in fallback sound if custom .ogg is missing
    SOUND_GAIN              = 0.15,                 -- Volume (0.0 to 1.0)
    SOUND_PITCH             = 0.80,                 -- Base pitch when SCALE_PITCH_WITH_RPM = false
    SCALE_PITCH_WITH_RPM    = true,                 -- Scale pitch dynamically with shaft RPM
    MIN_PITCH               = 0.65,                 -- Pitch at low RPM
    MAX_PITCH               = 1.15,                 -- Pitch at 512+ RPM
    SOUND_INTERVAL          = 30.0,                 -- Seconds between sound triggers while active
    MAX_HEAR_DISTANCE       = 12,                   -- Max distance (blocks) players can hear it
    SOUND_ONLY_SELF_POWERED = true,                 -- true = only play when fed steam; false = also play when spun passively by a shaft
}

local CONFIG = {
    TURBINE_KU                    = 1024,
    TURBINE_RPM                   = 512,
    STEAM_USE_PER_SEC             = 15,
    EXHAUST_PER_SEC               = 15,
    MIN_STEAM_TO_RUN              = 10,
    MAX_DIRECT_CHAIN              = 3,
    MAX_RPM_CAP                   = 3072,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_PORT_BACK                 = "kinetica_turbo_back.png",
    TEX_SIDE                      = "kinetica_turbo_side.png",
    TEX_FRONT_OFF                 = "kinetica_steam_turbo_front_off.png",
    TEX_FRONT_ON                  = "kinetica_steam_turbo_front_on.png",
}

local IDLE_NAME = "kinetica:turbine"

local TURBINE_KU        = CONFIG.TURBINE_KU
local TURBINE_RPM       = CONFIG.TURBINE_RPM
local STEAM_USE_PER_SEC = CONFIG.STEAM_USE_PER_SEC
local EXHAUST_PER_SEC   = CONFIG.EXHAUST_PER_SEC
local MAX_DIRECT_CHAIN  = CONFIG.MAX_DIRECT_CHAIN

kinetica.TURBINE_KU  = TURBINE_KU
kinetica.TURBINE_RPM = TURBINE_RPM

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

local function play_turbine_active_sound(pos, meta, eff_rpm, is_self_powered, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not RESOLVED_SOUND or RESOLVED_SOUND == "" then
        return
    end
    if SOUND_CONFIG.SOUND_ONLY_SELF_POWERED and not is_self_powered then
        return
    end

    local acc = meta:get_float("sfx_timer") + (dt or 1.0)
    if acc < (SOUND_CONFIG.SOUND_INTERVAL or 1.0) then
        meta:set_float("sfx_timer", acc)
        return
    end
    meta:set_float("sfx_timer", 0)

    local pitch = SOUND_CONFIG.SOUND_PITCH or 0.80
    if SOUND_CONFIG.SCALE_PITCH_WITH_RPM then
        local t = math.min(1.0, math.max(0.0, (eff_rpm or TURBINE_RPM) / TURBINE_RPM))
        local min_p = SOUND_CONFIG.MIN_PITCH or 0.65
        local max_p = SOUND_CONFIG.MAX_PITCH or 1.15
        pitch = min_p + t * (max_p - min_p)
    end

    core.sound_play(RESOLVED_SOUND, {
        pos               = pos,
        gain              = SOUND_CONFIG.SOUND_GAIN or 0.15,
        pitch             = pitch,
        max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 12,
    }, true)
end

local function is_turbine_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_turbine = is_turbine_node

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(kinetica.api.registration.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return kinetica.api.registration.ANIM_TIERS[#kinetica.api.registration.ANIM_TIERS].name
end

local function get_active_turbine_node_name(rpm, vis_spin)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (vis_spin == -1) and "ccw" or "cw"
    return IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
end

local function same_axle_axis(dir1, dir2)
    return (math.abs(dir1.x) == math.abs(dir2.x)) and
           (math.abs(dir1.z) == math.abs(dir2.z))
end

local function get_turbine_chain(pos, back_dir)
    local front_dir = {x = -back_dir.x, y = 0, z = -back_dir.z}
    local chain = {pos}

    for i = 1, 4 do
        local cpos  = {x = pos.x + front_dir.x * i, y = pos.y, z = pos.z + front_dir.z * i}
        local cnode = core.get_node(cpos)
        if is_turbine_node(cnode.name) and same_axle_axis(back_dir, core.facedir_to_dir(cnode.param2 % 4)) then
            table.insert(chain, cpos)
        else
            break
        end
    end

    for i = 1, 4 do
        local cpos  = {x = pos.x + back_dir.x * i, y = pos.y, z = pos.z + back_dir.z * i}
        local cnode = core.get_node(cpos)
        if is_turbine_node(cnode.name) and same_axle_axis(back_dir, core.facedir_to_dir(cnode.param2 % 4)) then
            table.insert(chain, cpos)
        else
            break
        end
    end

    return chain
end

local function wake_neighbor_turbines_and_pipes(pos)
    for _, dir in ipairs(kinetica.directions or {
        {x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=-1,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1}
    }) do
        local npos  = {x = pos.x + dir.x, y = pos.y + dir.y, z = pos.z + dir.z}
        local nnode = core.get_node(npos)
        if is_turbine_node(nnode.name) then
            local timer = core.get_node_timer(npos)
            if not timer:is_started() then timer:start(1.0) end
        elseif kinetica.is_pipe and kinetica.is_pipe(nnode.name) and kinetica.update_pipe_visuals then
            kinetica.update_pipe_visuals(npos, true)
        end
    end
end

function kinetica.refresh_turbine(pos, node)
    node = node or core.get_node(pos)
    local meta         = core.get_meta(pos)
    local horiz_param2 = (node.param2 or 0) % 4
    local back_dir     = core.facedir_to_dir(horiz_param2)
    local axis_sign    = back_dir.x + back_dir.z

    local chain = get_turbine_chain(pos, back_dir)
    meta:set_int("chain_len", #chain)

    if #chain > MAX_DIRECT_CHAIN then
        meta:set_int("chain_overloaded", 1)
        meta:set_int("source_active", 0)
        meta:set_int("source_ku", 0)
        meta:set_float("source_rpm", 0)
        meta:set_float("rpm", 0)
        return
    end

    meta:set_int("chain_overloaded", 0)

    if meta:get_int("self_powered") == 1 then
        meta:set_int("source_active", 1)
        meta:set_int("source_ku", TURBINE_KU)
        meta:set_float("source_rpm", TURBINE_RPM)
        meta:set_int("source_spin", axis_sign)
        meta:set_int("local_spin", axis_sign)
    else
        meta:set_int("source_active", 0)
        meta:set_int("source_ku", 0)
        meta:set_float("source_rpm", 0)
        meta:set_float("rpm", 0)
        meta:set_int("source_spin", axis_sign)
        meta:set_int("local_spin", axis_sign)
    end
end

local function sync_turbine_tier(pos)
    local node = core.get_node(pos)
    if not is_turbine_node(node.name) then return end

    local meta            = core.get_meta(pos)
    local horiz_param2    = (node.param2 or 0) % 4
    local back_dir        = core.facedir_to_dir(horiz_param2)
    local axis_sign       = back_dir.x + back_dir.z
    local is_self_powered = (meta:get_int("self_powered") == 1)
    local is_overstressed = (meta:get_int("network_overstressed") == 1)
    local net_rpm         = meta:get_float("rpm")
    local eff_rpm         = is_self_powered and TURBINE_RPM or net_rpm
    local should_spin_vis = (eff_rpm > 0) and (not is_overstressed) and (meta:get_int("chain_overloaded") == 0)

    if should_spin_vis then
        local canon_spin  = meta:get_int("spin_dir")
        if canon_spin == 0 then canon_spin = axis_sign end
        local vis_spin    = (canon_spin * axis_sign >= 0) and 1 or -1
        local target_node = get_active_turbine_node_name(eff_rpm, vis_spin)
        if node.name ~= target_node or node.param2 ~= horiz_param2 then
            core.swap_node(pos, {name = target_node, param2 = horiz_param2})
        end
    else
        if node.name ~= IDLE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = horiz_param2})
        end
    end
end

local function format_turbine_glasses_info(pos, node)
    local meta = core.get_meta(pos)
    local rpm  = meta:get_float("rpm")
    local is_self_powered = (meta:get_int("self_powered") == 1)
    local steam = meta:get_int("steam")
    local chain_len = meta:get_int("chain_len")
    local is_overloaded = (meta:get_int("chain_overloaded") == 1)
    local is_choked = (meta:get_int("exhaust_blocked") == 1)

    local state_str = "IDLE"
    if is_overloaded then state_str = "OVERLOADED (Max 3 Turbines)"
    elseif is_choked then state_str = "CHOKED (Exhaust Blocked)"
    elseif is_self_powered then state_str = "ACTIVE (Generating)"
    elseif rpm > 0 then state_str = "PASSIVE (Driven by Shaft)"
    end

    local T = kinetica.api and kinetica.api.telemetry or nil
    if not T then return "" end

    return table.concat({
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  Machine: Steam Turbine",
        "│  ● STATE: " .. state_str,
        "├─ KINETIC NETWORK ─────────────────",
        T.kv_row("Speed", string.format("%.1f RPM", is_self_powered and CONFIG.TURBINE_RPM or rpm)),
        T.kv_row("Supply", is_self_powered and (CONFIG.TURBINE_KU .. " KU") or "0 KU"),
        "├─ MACHINE DETAILS ─────────────────",
        T.kv_row("Internal Steam", steam),
        T.kv_row("Chain Length", string.format("%d / %d", chain_len, CONFIG.MAX_DIRECT_CHAIN)),
        "└───────────────────────────────────",
    }, "\n")
end

if kinetica.api and kinetica.api.telemetry then
    kinetica.api.telemetry.register_formatter(IDLE_NAME, format_turbine_glasses_info)
end

local function turbine_timer(pos, elapsed)
    local meta  = core.get_meta(pos)
    local node  = core.get_node(pos)
    local steam = meta:get_int("steam")

    local horiz_param2 = (node.param2 or 0) % 4
    local back_dir     = core.facedir_to_dir(horiz_param2)
    local axis_sign    = back_dir.x + back_dir.z
    local vent_pos     = {x = pos.x, y = pos.y + 1, z = pos.z}

    local vent_node        = core.get_node(vent_pos)
    local can_pipe_exhaust = kinetica.can_pipe_accept and kinetica.can_pipe_accept(vent_pos, "exhaust")
    local exhaust_blocked  = (vent_node.name ~= "air") and (not can_pipe_exhaust)

    meta:set_int("exhaust_blocked", exhaust_blocked and 1 or 0)
    meta:set_int("exhaust_piped",   can_pipe_exhaust and 1 or 0)

    local chain     = get_turbine_chain(pos, back_dir)
    local chain_len = #chain
    meta:set_int("chain_len", chain_len)

    if chain_len > MAX_DIRECT_CHAIN then
        meta:set_int("chain_overloaded", 1)
        meta:set_int("self_powered", 0)
        meta:set_int("source_active", 0)
        meta:set_int("source_ku", 0)
        meta:set_float("source_rpm", 0)
        meta:set_float("sfx_timer", 0)
        if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "Steam Turbine: OVERLOADED (Max 3 Turbines directly chained - use a Shaft!)")
        end
        if node.name ~= IDLE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = horiz_param2})
        end
        if kinetica.api and kinetica.api.network.update then
            kinetica.api.network.update(pos)
        end
        meta:set_string("glasses_info", format_turbine_glasses_info(pos, core.get_node(pos)))
        return true
    end

    meta:set_int("chain_overloaded", 0)

    local is_self_powered = false
    if not exhaust_blocked and steam >= CONFIG.MIN_STEAM_TO_RUN then
        is_self_powered = true
        steam = math.max(0, steam - STEAM_USE_PER_SEC)
        meta:set_int("steam", steam)

        if can_pipe_exhaust then
            kinetica.add_fluid_to_pipe(vent_pos, "exhaust", EXHAUST_PER_SEC)
        else
            core.add_particlespawner({
                amount     = 5,
                time       = 1.0,
                minpos     = {x = pos.x - 0.1, y = pos.y + 0.55, z = pos.z - 0.1},
                maxpos     = {x = pos.x + 0.1, y = pos.y + 0.65, z = pos.z + 0.1},
                minvel     = {x = -0.1, y = 0.6, z = -0.1},
                maxvel     = {x =  0.1, y = 1.2, z =  0.1},
                minexptime = 0.6,
                maxexptime = 1.2,
                minsize    = 1.5,
                maxsize    = 2.8,
                texture    = "mcl_particles_smoke.png",
            })
        end
    end

    meta:set_int("self_powered", is_self_powered and 1 or 0)
    if is_self_powered then
        meta:set_int("source_active", 1)
        meta:set_int("source_ku", TURBINE_KU)
        meta:set_float("source_rpm", TURBINE_RPM)
        meta:set_int("source_spin", axis_sign)
        meta:set_int("local_spin", axis_sign)
    else
        meta:set_int("source_active", 0)
        meta:set_int("source_ku", 0)
        meta:set_float("source_rpm", 0)
        meta:set_int("source_spin", axis_sign)
        meta:set_int("local_spin", axis_sign)
    end

    if kinetica.api and kinetica.api.network.update then
        kinetica.api.network.update(pos)
    end

    local is_overstressed = meta:get_int("network_overstressed") == 1
    local net_rpm         = meta:get_float("rpm")
    local eff_rpm         = is_self_powered and TURBINE_RPM or net_rpm
    local should_spin_vis = (is_self_powered or net_rpm > 0) and (not is_overstressed)

    if should_spin_vis then
        sync_turbine_tier(pos)
        play_turbine_active_sound(pos, meta, eff_rpm, is_self_powered, 1.0)
    else
        meta:set_float("sfx_timer", 0)
        if not is_overstressed and not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            if exhaust_blocked then
                meta:set_string("infotext", "Steam Turbine: CHOKED (Top Exhaust Vent is Blocked!)")
            else
                meta:set_string("infotext", string.format(
                    "Steam Turbine: Idle (Feed Steam to Right Port -> %d KU @ %d RPM)",
                    TURBINE_KU, TURBINE_RPM
                ))
            end
        end

        if core.get_node(pos).name ~= IDLE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = horiz_param2})
        end
    end

    meta:set_string("glasses_info", format_turbine_glasses_info(pos, core.get_node(pos)))
    return (steam > 0 or chain_len > 1)
end

local function make_turbine_anim(reverse, anim_length)
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
            length   = anim_length or 0.05,
        },
    }
end

local hyper_cw  = make_turbine_anim(false, 0.05)
local hyper_ccw = make_turbine_anim(true,  0.05)

if kinetica.api and kinetica.api.registration then
    kinetica.api.registration.register_rotary_machine(IDLE_NAME, {
        description = string.format("Steam Turbine (%d KU | %d RPM | Right: Steam In | Top: Exhaust)", TURBINE_KU, TURBINE_RPM),
        description_active = "Steam Turbine",
        paramtype2 = "facedir",
        groups_idle = {pickaxey = 2, steam_connectable = 1, pipe_steam = 1, pipe_exhaust = 1, rotational_source = 1, kinetica_turbine = 1},
        hardness = 3.5,
        blast_resistance = 3.5,
        sounds = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,
        
        tiles_idle = {
            CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, CONFIG.TEX_PORT_BACK,
            CONFIG.TEX_SIDE, CONFIG.TEX_FRONT_OFF, CONFIG.TEX_FRONT_OFF
        },
        tiles_active_cw = {
            CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, CONFIG.TEX_PORT_BACK,
            CONFIG.TEX_SIDE, hyper_ccw, hyper_cw
        },
        tiles_active_ccw = {
            CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, CONFIG.TEX_PORT_BACK,
            CONFIG.TEX_SIDE, hyper_cw, hyper_ccw
        },
        build_tier_tiles = function(tier, is_ccw)
            local t_cw  = make_turbine_anim(false, tier.length)
            local t_ccw = make_turbine_anim(true,  tier.length)
            if is_ccw then
                return {CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, t_cw, t_ccw}
            else
                return {CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, CONFIG.TEX_PORT_BACK, CONFIG.TEX_SIDE, t_ccw, t_cw}
            end
        end,

        on_construct = function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("steam", 0)
            meta:set_int("self_powered", 0)
            meta:set_int("source_active", 0)
            meta:set_int("source_ku", 0)
            meta:set_float("source_rpm", 0)
            meta:set_int("chain_len", 1)
            meta:set_int("exhaust_blocked", 0)
            meta:set_float("sfx_timer", 0)
            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                meta:set_string("infotext", string.format(
                    "Steam Turbine: Idle (Feed Steam to Right Port -> %d KU @ %d RPM)",
                    TURBINE_KU, TURBINE_RPM
                ))
            end
            core.get_node_timer(pos):start(1.0)
            wake_neighbor_turbines_and_pipes(pos)
        end,

        after_dig_node = function(pos)
            wake_neighbor_turbines_and_pipes(pos)
        end,

        on_timer = turbine_timer,
    })
end

core.register_alias("kinetica:turbine_active",     "kinetica:turbine_hyper_cw")
core.register_alias("kinetica:turbine_active_cw",  "kinetica:turbine_hyper_cw")
core.register_alias("kinetica:turbine_active_ccw", "kinetica:turbine_hyper_ccw")

core.register_lbm({
    label             = "Wake kinetica Steam Turbines on chunk load",
    name              = "kinetica:wake_turbines_lbm",
    nodenames         = {"group:kinetica_turbine"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(1.0)
        end
    end,
})

core.register_craft({
    output = "kinetica:turbine",
    recipe = {
        {"kinetica:sheet_copper", "kinetica:steam_pipe",    "kinetica:sheet_copper"},
        {"kinetica:sheet_iron",   "kinetica:copper_casing", "kinetica:sheet_iron"},
        {"kinetica:sheet_copper", "kinetica:shaft",         "kinetica:sheet_copper"},
    },
})
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
    SOUND_INTERVAL          = 0.01,                 -- Seconds between sound triggers while active
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
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
        { name = "ultra",  max_rpm = 3072, length = 0.03 },
    },
    TEX_PORT_BACK                 = "kinetica_turbo_back.png",
    TEX_SIDE                      = "kinetica_turbo_side.png",
    TEX_FRONT_OFF                 = "kinetica_steam_turbo_front_off.png",
    TEX_FRONT_ON                  = "kinetica_steam_turbo_front_on.png",
}

local IDLE_NAME       = "kinetica:turbine"
local ACTIVE_NAME     = "kinetica:turbine_active"
local ACTIVE_CW_NAME  = "kinetica:turbine_active_cw"
local ACTIVE_CCW_NAME = "kinetica:turbine_active_ccw"

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
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_active_turbine_node_name(rpm, vis_spin)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (vis_spin == -1) and "ccw" or "cw"
    local candidate = IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then
        return candidate
    end
    return ACTIVE_NAME
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

kinetica._tier_node_map   = kinetica._tier_node_map   or {}
kinetica._tier_sync_funcs = kinetica._tier_sync_funcs or {}
kinetica._tier_sync_funcs[IDLE_NAME] = sync_turbine_tier

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
        if kinetica.update_network then
            kinetica.update_network(pos)
        end
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

    if is_self_powered and node.name ~= ACTIVE_NAME then
        core.swap_node(pos, {name = ACTIVE_NAME, param2 = horiz_param2})
    end

    if kinetica.update_network then
        kinetica.update_network(pos)
    end

    local is_overstressed = meta:get_int("network_overstressed") == 1
    local net_rpm         = meta:get_float("rpm")
    local eff_rpm         = is_self_powered and TURBINE_RPM or net_rpm
    local should_spin_vis = (is_self_powered or net_rpm > 0) and (not is_overstressed)

    if should_spin_vis then
        sync_turbine_tier(pos)
        -- Play sound ONLY while the turbine is actively spinning and not overstressed
        play_turbine_active_sound(pos, meta, eff_rpm, is_self_powered, 1.0)
        return true
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
        return (steam > 0 or chain_len > 1)
    end
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

local base_groups   = {pickaxey = 2, steam_connectable = 1, pipe_steam = 1, pipe_exhaust = 1, rotational_source = 1, kinetica_turbine = 1}
local active_groups = {pickaxey = 2, not_in_creative_inventory = 1, steam_connectable = 1, pipe_steam = 1, pipe_exhaust = 1, rotational_source = 1, kinetica_turbine = 1}

local function register_turbine_variant(node_name, back_tile, front_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and string.format("Steam Turbine (%d KU | %d RPM | Right: Steam In | Top: Exhaust)", TURBINE_KU, TURBINE_RPM)
            or  "Steam Turbine",
        tiles = {
            CONFIG.TEX_PORT_BACK,
            CONFIG.TEX_SIDE,
            CONFIG.TEX_PORT_BACK,
            CONFIG.TEX_SIDE,
            back_tile,
            front_tile,
        },
        paramtype2 = "facedir",
        drop = is_base and nil or IDLE_NAME,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 3.5,
        _mcl_blast_resistance = 3.5,
        sounds = mcl_sounds.node_sound_metal_defaults(),

        on_construct = is_base and function(pos)
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
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = function(pos)
            wake_neighbor_turbines_and_pipes(pos)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,

        on_timer = turbine_timer,
    })
end

register_turbine_variant(IDLE_NAME, CONFIG.TEX_FRONT_OFF, CONFIG.TEX_FRONT_OFF, true)

local hyper_cw  = make_turbine_anim(false, 0.05)
local hyper_ccw = make_turbine_anim(true,  0.05)
register_turbine_variant(ACTIVE_NAME,     hyper_ccw, hyper_cw,  false)
register_turbine_variant(ACTIVE_CW_NAME,  hyper_ccw, hyper_cw,  false)
register_turbine_variant(ACTIVE_CCW_NAME, hyper_cw,  hyper_ccw, false)

kinetica._tier_node_map[ACTIVE_NAME]     = {canonical = ACTIVE_NAME, base = IDLE_NAME}
kinetica._tier_node_map[ACTIVE_CW_NAME]  = {canonical = ACTIVE_NAME, base = IDLE_NAME}
kinetica._tier_node_map[ACTIVE_CCW_NAME] = {canonical = ACTIVE_NAME, base = IDLE_NAME}

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local t_cw  = make_turbine_anim(false, tier.length)
    local t_ccw = make_turbine_anim(true,  tier.length)

    local name_cw  = IDLE_NAME .. "_" .. tier.name .. "_cw"
    local name_ccw = IDLE_NAME .. "_" .. tier.name .. "_ccw"

    register_turbine_variant(name_cw,  t_ccw, t_cw,  false)
    register_turbine_variant(name_ccw, t_cw,  t_ccw, false)

    kinetica._tier_node_map[name_cw]  = {canonical = ACTIVE_NAME, base = IDLE_NAME}
    kinetica._tier_node_map[name_ccw] = {canonical = ACTIVE_NAME, base = IDLE_NAME}
end

core.register_on_mods_loaded(function()
    kinetica.is_turbine = is_turbine_node
end)

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
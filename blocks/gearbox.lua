kinetica = kinetica or {}

local CONFIG = {
    FRICTION_FINE_KU = 1,
    MAX_RPM_CAP      = 1024,
    TIMER_INTERVAL   = 0.25,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    STRIP_CW_CCW_FROM_TEXT        = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_SOLID_FACE    = "kinetica_andisite_casing.png",
    TEX_GEAR_IDLE     = "kinetica_gear_box_gear_side.png",
    TEX_GEAR_ACTIVE   = "kinetica_gear_box_gear_side_on.png",
    TEX_SHAFT_OVERLAY = "kinetica_shaft_connecting_overlay.png",
}

local HORIZ_IDLE    = "kinetica:gearbox"
local HORIZ_ACT_CW  = "kinetica:gearbox_active_cw"
local HORIZ_ACT_CCW = "kinetica:gearbox_active_ccw"

local VERT_IDLE     = "kinetica:gearbox_vertical"
local VERT_ACT_CW   = "kinetica:gearbox_vertical_active_cw"
local VERT_ACT_CCW  = "kinetica:gearbox_vertical_active_ccw"

local ALL_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local raw_get_node  = core.get_node
local raw_swap_node = core.swap_node

local function is_vert_gearbox(name)
    if not name then return false end
    return name == VERT_IDLE or string.sub(name, 1, #VERT_IDLE + 1) == (VERT_IDLE .. "_")
end

local function is_horiz_gearbox(name)
    if not name or is_vert_gearbox(name) then return false end
    return name == HORIZ_IDLE or string.sub(name, 1, #HORIZ_IDLE + 1) == (HORIZ_IDLE .. "_")
end

local function is_any_gearbox(name)
    return is_horiz_gearbox(name) or is_vert_gearbox(name)
end
kinetica.is_gearbox = is_any_gearbox

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function is_blocked_by_solid_face(pos, node)
    if not kinetica.has_axle_port then return false end
    for _, d in ipairs(ALL_DIRS) do
        if not kinetica.has_axle_port(node, d) then
            local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
            local nnode = raw_get_node(npos)
            local rev   = {x = -d.x, y = -d.y, z = -d.z}
            if kinetica.has_axle_port(nnode, rev) then
                local nmeta = core.get_meta(npos)
                if nmeta:get_float("rpm") > 0 or nmeta:get_int("source_active") == 1 then
                    return true
                end
            end
        end
    end
    return false
end

local function clean_cw_ccw_text(str)
    if not str or str == "" then return "" end
    if not CONFIG.STRIP_CW_CCW_FROM_TEXT then return str end
    str = string.gsub(str, "%s*%[CW%]", "")
    str = string.gsub(str, "%s*%[CCW%]", "")
    str = string.gsub(str, "%s*%(CW%)", "")
    str = string.gsub(str, "%s*%(CCW%)", "")
    str = string.gsub(str, "ACTIVE CW", "ACTIVE")
    str = string.gsub(str, "ACTIVE CCW", "ACTIVE")
    str = string.gsub(str, "Active CW", "Active")
    str = string.gsub(str, "Active CCW", "Active")
    str = string.gsub(str, "%s+CW([%s%)%]%|])", "%1")
    str = string.gsub(str, "%s+CCW([%s%)%]%|])", "%1")
    return str
end

local function format_gearbox_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local now       = math.floor(core.get_gametime())
    local is_vert   = is_vert_gearbox(node.name)
    local is_idle   = (node.name == HORIZ_IDLE or node.name == VERT_IDLE)
    local is_active = (not is_idle) and (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))
    local blocked   = (not is_active) and is_blocked_by_solid_face(pos, node)

    local state_str = is_active and "ACTIVE" or (blocked and "BLOCKED (Solid Face)" or "IDLE")
    local ports_str = is_vert and "4-Way Vertical (+Y, -Y, Horizontal)" or "4-Way Horizontal (+X, -X, +Z, -Z)"

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Block:  " .. (is_vert and "Vertical Gearbox" or "Gearbox"),
        "State:  " .. state_str,
        string.format("Speed:  %.1f RPM", is_active and rpm or 0),
        string.format("Power:  %d / %d KU Avail (-%d KU Fine)", is_active and avail_ku or 0, supply_ku, CONFIG.FRICTION_FINE_KU),
        "Ports:  " .. ports_str,
    }, "\n")
end

local function sync_gearbox_tier_and_text(pos)
    local node = raw_get_node(pos)
    if not is_any_gearbox(node.name) then return end

    local is_vert   = is_vert_gearbox(node.name)
    local base_name = is_vert and VERT_IDLE or HORIZ_IDLE
    local meta      = core.get_meta(pos)
    local now       = math.floor(core.get_gametime())
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local spin_dir  = meta:get_int("spin_dir")
    local is_active = (node.name ~= base_name) and (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))

    if is_active then
        local dir_tag = "cw"
        if spin_dir == -1 or string.sub(node.name, -4) == "_ccw" then
            dir_tag = "ccw"
        end
        local tier_name   = get_anim_tier_name(rpm)
        local target_name = base_name .. "_" .. tier_name .. "_" .. dir_tag
        if node.name ~= target_name and core.registered_nodes[target_name] then
            raw_swap_node(pos, {name = target_name, param2 = node.param2})
            node.name = target_name
        end
    end

    meta:set_string("glasses_info", format_gearbox_glasses_info(pos, node))

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        local cur_info = meta:get_string("infotext")
        if cur_info ~= "" then
            meta:set_string("infotext", clean_cw_ccw_text(cur_info))
        elseif is_active then
            meta:set_string("infotext", string.format(
                "%s: ACTIVE (-%d KU fine | %d KU avail / %d KU total | %.0f RPM)",
                is_vert and "Vertical Gearbox" or "Gearbox",
                CONFIG.FRICTION_FINE_KU, avail_ku, supply_ku, rpm
            ))
        else
            meta:set_string("infotext", string.format(
                "%s: Idle (%d KU Fine | Shares KU & RPM on Demand)",
                is_vert and "Vertical Gearbox" or "Gearbox",
                CONFIG.FRICTION_FINE_KU
            ))
        end
    end

    local timer = core.get_node_timer(pos)
    if is_active and not timer:is_started() then
        timer:start(CONFIG.TIMER_INTERVAL)
    end
end

kinetica._tier_node_map      = kinetica._tier_node_map      or {}
kinetica._tier_sync_funcs    = kinetica._tier_sync_funcs    or {}
kinetica._glasses_formatters = kinetica._glasses_formatters or {}

kinetica._tier_sync_funcs[HORIZ_IDLE]    = sync_gearbox_tier_and_text
kinetica._tier_sync_funcs[VERT_IDLE]     = sync_gearbox_tier_and_text
kinetica._glasses_formatters[HORIZ_IDLE] = format_gearbox_glasses_info
kinetica._glasses_formatters[VERT_IDLE]  = format_gearbox_glasses_info

if not kinetica.get_glasses_info then
    function kinetica.get_glasses_info(pos, node)
        node = node or raw_get_node(pos)
        for prefix, fn in pairs(kinetica._glasses_formatters) do
            if node.name == prefix or string.sub(node.name or "", 1, #prefix + 1) == (prefix .. "_") then
                return fn(pos, node)
            end
        end
        return core.get_meta(pos):get_string("glasses_info")
    end
end

local function install_tier_solver_bridge()
    if kinetica._tier_bridge_installed or not kinetica.update_network then
        return
    end
    kinetica._tier_bridge_installed = true

    local orig_update_network = kinetica.update_network
    local orig_set_node_idle  = kinetica.set_node_idle
    local orig_has_axle_port  = kinetica.has_axle_port
    local in_solver_depth     = 0
    local touched_positions   = {}

    if orig_has_axle_port then
        function kinetica.has_axle_port(node, d)
            if node and kinetica._tier_node_map[node.name] then
                node = {name = kinetica._tier_node_map[node.name].canonical, param2 = node.param2}
            end
            return orig_has_axle_port(node, d)
        end
    end

    function core.get_node(pos)
        local n = raw_get_node(pos)
        if in_solver_depth > 0 and n and kinetica._tier_node_map[n.name] then
            local info = kinetica._tier_node_map[n.name]
            touched_positions[core.hash_node_position(pos)] = {
                pos  = {x = pos.x, y = pos.y, z = pos.z},
                base = info.base,
            }
            return {name = info.canonical, param1 = n.param1, param2 = n.param2}
        end
        return n
    end
    minetest.get_node = core.get_node

    function core.swap_node(pos, node)
        raw_swap_node(pos, node)
        if in_solver_depth > 0 and node and node.name then
            for base_prefix, _ in pairs(kinetica._tier_sync_funcs) do
                if node.name == base_prefix or string.sub(node.name, 1, #base_prefix + 1) == (base_prefix .. "_") then
                    touched_positions[core.hash_node_position(pos)] = {
                        pos  = {x = pos.x, y = pos.y, z = pos.z},
                        base = base_prefix,
                    }
                end
            end
        end
    end
    minetest.swap_node = core.swap_node

    if orig_set_node_idle then
        function kinetica.set_node_idle(pos, node, reason)
            in_solver_depth = in_solver_depth + 1
            if node and kinetica._tier_node_map[node.name] then
                node = {name = kinetica._tier_node_map[node.name].canonical, param2 = node.param2}
            end
            orig_set_node_idle(pos, node, clean_cw_ccw_text(reason))
            in_solver_depth = in_solver_depth - 1

            local real_n = raw_get_node(pos)
            for base_prefix, sync_fn in pairs(kinetica._tier_sync_funcs) do
                if real_n.name == base_prefix or string.sub(real_n.name, 1, #base_prefix + 1) == (base_prefix .. "_") then
                    sync_fn(pos)
                end
            end
        end
    end

    function kinetica.update_network(pos)
        in_solver_depth = in_solver_depth + 1
        orig_update_network(pos)
        in_solver_depth = in_solver_depth - 1

        if in_solver_depth == 0 and next(touched_positions) then
            local batch = touched_positions
            touched_positions = {}
            for _, entry in pairs(batch) do
                local sync_fn = kinetica._tier_sync_funcs[entry.base]
                if sync_fn then
                    sync_fn(entry.pos)
                end
            end
        end
    end
end

install_tier_solver_bridge()
core.register_on_mods_loaded(install_tier_solver_bridge)

local function gearbox_timer(pos, elapsed)
    install_tier_solver_bridge()
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    if now < meta:get_int("lit_until") then
        sync_gearbox_tier_and_text(pos)
        return true
    end

    if kinetica.update_network then
        kinetica.update_network(pos)
    end

    if math.floor(core.get_gametime()) < meta:get_int("lit_until") then
        sync_gearbox_tier_and_text(pos)
        return true
    end

    local node = raw_get_node(pos)
    if is_blocked_by_solid_face(pos, node) then
        if kinetica.set_node_idle then
            kinetica.set_node_idle(pos, node, "Gearbox: Blocked (Power hitting solid casing!)")
        end
    else
        if kinetica.set_node_idle then
            kinetica.set_node_idle(pos, node)
        end
    end
    sync_gearbox_tier_and_text(pos)
    return false
end

local function make_gear_overlay(reverse, anim_length)
    local gear  = CONFIG.TEX_GEAR_ACTIVE
    local shaft = CONFIG.TEX_SHAFT_OVERLAY
    local gear_strip
    local shaft_strip

    if reverse then
        gear_strip = "[combine:16x64" ..
            ":0,0="  .. gear .. "\\^[sheet\\:1x3\\:0,0" ..
            ":0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,2" ..
            ":0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,1" ..
            ":0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,2"

        shaft_strip = "[combine:16x64" ..
            ":0,0="  .. shaft .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. shaft .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. shaft .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. shaft .. "\\^[sheet\\:1x4\\:0,1"
    else
        gear_strip = "[combine:16x64" ..
            ":0,0="  .. gear .. "\\^[sheet\\:1x3\\:0,0" ..
            ":0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,1" ..
            ":0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,2" ..
            ":0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,1"

        shaft_strip = shaft
    end

    local final_tex = "(" .. gear_strip .. ")^(" .. shaft_strip .. ")"
    return {
        name = final_tex,
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.4,
        },
    }
end

local idle_face  = "[combine:16x16:0,0=" .. CONFIG.TEX_GEAR_IDLE .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local SOLID_FACE = CONFIG.TEX_SOLID_FACE

local function on_horiz_gearbox_construct(pos)
    local node = raw_get_node(pos)
    if node.param2 ~= 0 then
        raw_swap_node(pos, {name = node.name, param2 = 0})
    end
    if kinetica.set_node_idle then
        kinetica.set_node_idle(pos, raw_get_node(pos))
    end
    sync_gearbox_tier_and_text(pos)
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update(pos)
    end
end

local function on_vert_gearbox_construct(pos)
    local node = raw_get_node(pos)
    local canon_p2 = (node.param2 or 0) % 2
    if node.param2 ~= canon_p2 then
        raw_swap_node(pos, {name = node.name, param2 = canon_p2})
    end
    if kinetica.set_node_idle then
        kinetica.set_node_idle(pos, raw_get_node(pos))
    end
    sync_gearbox_tier_and_text(pos)
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update(pos)
    end
end

local function on_gearbox_dig(pos)
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update(pos)
    end
end

local base_groups   = {pickaxey = 1, kinetic_receiver = 1, kinetica_gearbox = 1}
local active_groups = {pickaxey = 1, kinetic_receiver = 1, kinetica_gearbox = 1, not_in_creative_inventory = 1}

local function register_horiz_gearbox_variant(node_name, x_tile, z_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and "Gearbox (1 KU Fine | Shares KU & RPM on Demand)"
            or  "Gearbox",
        tiles = {
            SOLID_FACE,
            SOLID_FACE,
            x_tile,
            x_tile,
            z_tile,
            z_tile,
        },
        paramtype2 = "facedir",
        drop = is_base and nil or HORIZ_IDLE,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_metal_defaults(),
        on_construct = is_base and on_horiz_gearbox_construct or nil,
        after_dig_node = on_gearbox_dig,
        on_timer = gearbox_timer,
    })
end

local function register_vert_gearbox_variant(node_name, y_tile, z_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and "Vertical Gearbox (1 KU Fine | Up/Down & Front/Back Relay)"
            or  "Vertical Gearbox",
        tiles = {
            y_tile,
            y_tile,
            SOLID_FACE,
            SOLID_FACE,
            z_tile,
            z_tile,
        },
        paramtype2 = "facedir",
        drop = is_base and nil or VERT_IDLE,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_metal_defaults(),
        on_construct = is_base and on_vert_gearbox_construct or nil,
        after_dig_node = on_gearbox_dig,
        on_timer = gearbox_timer,
    })
end

register_horiz_gearbox_variant(HORIZ_IDLE, idle_face, idle_face, true)
register_vert_gearbox_variant(VERT_IDLE,   idle_face, idle_face, true)

local med_cw  = make_gear_overlay(false, 0.24)
local med_ccw = make_gear_overlay(true,  0.24)

register_horiz_gearbox_variant(HORIZ_ACT_CW,  med_ccw, med_cw,  false)
register_horiz_gearbox_variant(HORIZ_ACT_CCW, med_cw,  med_ccw, false)
register_vert_gearbox_variant(VERT_ACT_CW,    med_cw,  med_ccw, false)
register_vert_gearbox_variant(VERT_ACT_CCW,   med_ccw, med_cw,  false)

kinetica._tier_node_map[HORIZ_ACT_CW]  = {canonical = HORIZ_ACT_CW,  base = HORIZ_IDLE}
kinetica._tier_node_map[HORIZ_ACT_CCW] = {canonical = HORIZ_ACT_CCW, base = HORIZ_IDLE}
kinetica._tier_node_map[VERT_ACT_CW]   = {canonical = VERT_ACT_CW,   base = VERT_IDLE}
kinetica._tier_node_map[VERT_ACT_CCW]  = {canonical = VERT_ACT_CCW,  base = VERT_IDLE}

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local t_cw  = make_gear_overlay(false, tier.length)
    local t_ccw = make_gear_overlay(true,  tier.length)

    local h_cw  = HORIZ_IDLE .. "_" .. tier.name .. "_cw"
    local h_ccw = HORIZ_IDLE .. "_" .. tier.name .. "_ccw"
    register_horiz_gearbox_variant(h_cw,  t_ccw, t_cw,  false)
    register_horiz_gearbox_variant(h_ccw, t_cw,  t_ccw, false)
    kinetica._tier_node_map[h_cw]  = {canonical = HORIZ_ACT_CW,  base = HORIZ_IDLE}
    kinetica._tier_node_map[h_ccw] = {canonical = HORIZ_ACT_CCW, base = HORIZ_IDLE}

    local v_cw  = VERT_IDLE .. "_" .. tier.name .. "_cw"
    local v_ccw = VERT_IDLE .. "_" .. tier.name .. "_ccw"
    register_vert_gearbox_variant(v_cw,  t_cw,  t_ccw, false)
    register_vert_gearbox_variant(v_ccw, t_ccw, t_cw,  false)
    kinetica._tier_node_map[v_cw]  = {canonical = VERT_ACT_CW,  base = VERT_IDLE}
    kinetica._tier_node_map[v_ccw] = {canonical = VERT_ACT_CCW, base = VERT_IDLE}
end

core.register_alias("kinetica:gearbox_active",          HORIZ_ACT_CW)
core.register_alias("kinetica:gearbox_vertical_active", VERT_ACT_CW)

core.register_lbm({
    label             = "Sync kinetica Gearboxes on chunk load",
    name              = "kinetica:sync_gearboxes_lbm",
    nodenames         = {"group:kinetica_gearbox"},
    run_at_every_load = true,
    action = function(pos, node)
        sync_gearbox_tier_and_text(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

core.register_craft({
    output = "kinetica:gearbox",
    recipe = {
        {"",               "kinetica:shaft",           ""},
        {"kinetica:shaft", "kinetica:andesite_casing", "kinetica:shaft"},
        {"",               "kinetica:shaft",           ""},
    },
})

core.register_craft({
    output = "kinetica:gearbox_vertical",
    recipe = {
        {"kinetica:gearbox"},
    },
})

core.register_craft({
    output = "kinetica:gearbox",
    recipe = {
        {"kinetica:gearbox_vertical"},
    },
})
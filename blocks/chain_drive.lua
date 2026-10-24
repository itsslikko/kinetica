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
    TEX_FRONT         = "kinetica_chain_drive_front.png",
    TEX_SIDE          = "kinetica_chain_drive_side.png",
    TEX_SHAFT_OVERLAY = "kinetica_shaft_connecting_overlay.png",
}

local IDLE    = "kinetica:chain_drive"
local ACT_CW  = "kinetica:chain_drive_active_cw"
local ACT_CCW = "kinetica:chain_drive_active_ccw"

local DIRS = {
    {x =  1, y =  0, z =  0}, {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0}, {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1}, {x =  0, y =  0, z = -1},
}

local function is_chain_drive(name)
    if not name then return false end
    return name == IDLE or string.sub(name, 1, #IDLE + 1) == (IDLE .. "_")
end
kinetica.is_chain_drive = is_chain_drive

local function add(p, d)
    return {x = p.x + d.x, y = p.y + d.y, z = p.z + d.z}
end

local function abs_axis(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = math.abs(d.x), y = math.abs(d.y), z = math.abs(d.z)}
end

local function axis_to_param2(axis)
    if axis.y ~= 0 then return 4
    elseif axis.x ~= 0 then return 1
    else return 0 end
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

local function format_chain_drive_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local now       = math.floor(core.get_gametime())
    local is_active = (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))

    local ax = abs_axis(node.param2)
    local axis_lbl = (ax.y ~= 0) and "Vertical (Y)" or ((ax.x ~= 0) and "East-West (X)" or "North-South (Z)")

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Block:  Encased Chain Drive",
        "State:  " .. (is_active and "ACTIVE" or "IDLE"),
        string.format("Speed:  %.1f RPM", is_active and rpm or 0),
        string.format("Power:  %d / %d KU Avail (-%d KU Fine)", is_active and avail_ku or 0, supply_ku, CONFIG.FRICTION_FINE_KU),
        "Axle:   " .. axis_lbl,
    }, "\n")
end

local raw_get_node  = core.get_node
local raw_swap_node = core.swap_node

local function sync_chain_drive_tier_and_text(pos)
    local node = raw_get_node(pos)
    if not is_chain_drive(node.name) then return end

    local meta      = core.get_meta(pos)
    local now       = math.floor(core.get_gametime())
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local spin_dir  = meta:get_int("spin_dir")
    local is_active = (node.name ~= IDLE) and (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))

    if is_active then
        local back      = core.facedir_to_dir(node.param2) or {x = 0, y = 0, z = 1}
        local axis_sign = back.x + back.y + back.z
        local vis       = (spin_dir * axis_sign >= 0) and 1 or -1
        local dir_tag   = (vis == 1) and "cw" or "ccw"
        local tier_name   = get_anim_tier_name(rpm)
        local target_name = IDLE .. "_" .. tier_name .. "_" .. dir_tag
        if node.name ~= target_name and core.registered_nodes[target_name] then
            raw_swap_node(pos, {name = target_name, param2 = node.param2})
            node.name = target_name
        end
    end

    meta:set_string("glasses_info", format_chain_drive_glasses_info(pos, node))

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        local cur_info = meta:get_string("infotext")
        if cur_info ~= "" then
            meta:set_string("infotext", clean_cw_ccw_text(cur_info))
        elseif is_active then
            meta:set_string("infotext", string.format(
                "Encased Chain Drive: ACTIVE (-%d KU fine | %d KU avail / %d KU total | %.0f RPM)",
                CONFIG.FRICTION_FINE_KU, avail_ku, supply_ku, rpm
            ))
        else
            meta:set_string("infotext", string.format(
                "Encased Chain Drive: Idle (%d KU Fine | Shares KU & RPM on Demand)",
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

kinetica._tier_sync_funcs[IDLE]    = sync_chain_drive_tier_and_text
kinetica._glasses_formatters[IDLE] = format_chain_drive_glasses_info

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

local function chain_drive_timer(pos, elapsed)
    install_tier_solver_bridge()
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)

    if now < meta:get_int("lit_until") then
        sync_chain_drive_tier_and_text(pos)
        return true
    end

    if kinetica.update_network then
        kinetica.update_network(pos)
    end

    if math.floor(core.get_gametime()) < meta:get_int("lit_until") then
        sync_chain_drive_tier_and_text(pos)
        return true
    end

    if kinetica.set_node_idle then
        kinetica.set_node_idle(pos, raw_get_node(pos))
    end
    sync_chain_drive_tier_and_text(pos)
    return false
end

local function preferred_axis(pos)
    for _, d in ipairs(DIRS) do
        local nn = raw_get_node(add(pos, d))
        if kinetica.is_shaft and kinetica.is_shaft(nn.name)
           and kinetica.is_Aligned_With_Dir(nn.param2, d) then
            return {x = math.abs(d.x), y = math.abs(d.y), z = math.abs(d.z)}
        end
    end
    for _, d in ipairs(DIRS) do
        local nn = raw_get_node(add(pos, d))
        if is_chain_drive(nn.name) then
            return abs_axis(nn.param2)
        end
    end
    return nil
end

local function look_axis(placer)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if ay >= ax and ay >= az then return {x = 0, y = 1, z = 0}
    elseif ax >= az then return {x = 1, y = 0, z = 0}
    else return {x = 0, y = 0, z = 1} end
end

local function chain_drive_on_place(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end

    local under_node = raw_get_node(pointed_thing.under)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking then
        return under_def.on_rightclick(pointed_thing.under, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local place_pos = pointed_thing.above
    if under_def and under_def.buildable_to then
        place_pos = pointed_thing.under
    end

    local axis = nil
    if not sneaking then
        axis = preferred_axis(place_pos)
    end
    if not axis then
        axis = look_axis(placer)
    end

    return core.item_place_node(itemstack, placer, pointed_thing, axis_to_param2(axis))
end

local function make_chain_overlay(reverse, anim_length)
    local casing = CONFIG.TEX_FRONT
    local shaft  = CONFIG.TEX_SHAFT_OVERLAY

    local tex = "[combine:16x64" ..
        ":0,0="  .. casing ..
        ":0,16=" .. casing ..
        ":0,32=" .. casing ..
        ":0,48=" .. casing

    if reverse then
        tex = tex ..
            ":0,0=("  .. shaft .. "\\^[sheet\\:1x4\\:0,0)" ..
            ":0,16=(" .. shaft .. "\\^[sheet\\:1x4\\:0,3)" ..
            ":0,32=(" .. shaft .. "\\^[sheet\\:1x4\\:0,2)" ..
            ":0,48=(" .. shaft .. "\\^[sheet\\:1x4\\:0,1)"
    else
        tex = tex .. ":0,0=" .. shaft
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

local idle_face = "[combine:16x16:0,0=" .. CONFIG.TEX_FRONT .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local SIDE      = CONFIG.TEX_SIDE

local base_groups   = {pickaxey = 1, kinetic_receiver = 1, kinetica_chain_drive = 1}
local active_groups = {pickaxey = 1, kinetic_receiver = 1, kinetica_chain_drive = 1, not_in_creative_inventory = 1}

local function register_chain_drive_variant(node_name, back_tile, front_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and "Encased Chain Drive (1 KU Fine | Shares KU & RPM on Demand)"
            or  "Encased Chain Drive",
        tiles = {
            SIDE, SIDE, SIDE, SIDE,
            back_tile,
            front_tile,
        },
        paramtype2 = "facedir",
        on_place = is_base and chain_drive_on_place or nil,
        drop = IDLE,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_wood_defaults(),

        on_construct = is_base and function(pos)
            local node = raw_get_node(pos)
            local canon_p2 = axis_to_param2(abs_axis(node.param2))
            if node.param2 ~= canon_p2 then
                raw_swap_node(pos, {name = node.name, param2 = canon_p2})
            end
            if kinetica.set_node_idle then
                kinetica.set_node_idle(pos, raw_get_node(pos))
            end
            sync_chain_drive_tier_and_text(pos)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = function(pos)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,

        on_timer = chain_drive_timer,
    })
end

register_chain_drive_variant(IDLE, idle_face, idle_face, true)

local med_cw  = make_chain_overlay(false, 0.24)
local med_ccw = make_chain_overlay(true,  0.24)
register_chain_drive_variant(ACT_CW,  med_ccw, med_cw,  false)
register_chain_drive_variant(ACT_CCW, med_cw,  med_ccw, false)

kinetica._tier_node_map[ACT_CW]  = {canonical = ACT_CW,  base = IDLE}
kinetica._tier_node_map[ACT_CCW] = {canonical = ACT_CCW, base = IDLE}

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local t_cw  = make_chain_overlay(false, tier.length)
    local t_ccw = make_chain_overlay(true,  tier.length)

    local name_cw  = IDLE .. "_" .. tier.name .. "_cw"
    local name_ccw = IDLE .. "_" .. tier.name .. "_ccw"

    register_chain_drive_variant(name_cw,  t_ccw, t_cw,  false)
    register_chain_drive_variant(name_ccw, t_cw,  t_ccw, false)

    kinetica._tier_node_map[name_cw]  = {canonical = ACT_CW,  base = IDLE}
    kinetica._tier_node_map[name_ccw] = {canonical = ACT_CCW, base = IDLE}
end

core.register_lbm({
    label             = "Sync kinetica Chain Drives on chunk load",
    name              = "kinetica:sync_chain_drives_lbm",
    nodenames         = {"group:kinetica_chain_drive"},
    run_at_every_load = true,
    action = function(pos, node)
        sync_chain_drive_tier_and_text(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

core.register_craft({
    output = "kinetica:chain_drive 2",
    recipe = {
        {"mcl_core:iron_ingot", "mcl_core:iron_ingot",    "mcl_core:iron_ingot"},
        {"kinetica:shaft",      "kinetica:andesite_casing", "kinetica:shaft"},
        {"mcl_core:iron_ingot", "mcl_core:iron_ingot",    "mcl_core:iron_ingot"},
    },
})